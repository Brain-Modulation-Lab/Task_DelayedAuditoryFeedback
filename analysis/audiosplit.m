%% audiosplit.m  —  Slice long DAF WAV into per-trial files
% Alignment: user enters first beep time in from praat
% Task anchor: first trial's visual onset from TRIALS.TSV.
% Mapping: audio_time = trials_time + (beep_audio - first_visual_onset_in_trials)

%% USER CONFIG
cfg = struct();

% Point to a WAV file
% cfg.audio_path = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/analysis/sub-daftestsub_ses-intraop_task-daf_run-24.wav';
% cfg.trials_path = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/analysis/sub-daftestsub_ses-intraop_task-daf_run-24_trials.tsv';
%cfg.events_path = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAud\itoryFeedback/analysis/sub-daftestsub_ses-intraop_task-daf_run-24_events.tsv';

cfg.audio_path = 'C:\bml_DBS\sub-DM1053\ses-preop\audio\251023_0750.wav'; 
cfg.trials_path = 'C:\bml_DBS\sub-DM1053\ses-preop\task\sub-DM1053_ses-preop_task-daf_run-03_trials.tsv'; 

cfg.output_dir = 'trials_out';
cfg.channel_index = 1; % which channel to export (choose from praat)

% Trial end policy
cfg.use_next_onset = true; % true: end at next onset (with guard); false: fixed duration
cfg.trial_duration_s = 6.0; % used if use_next_onset == false
cfg.boundary_guard_s = 0.05; % keep this much before next onset
cfg.max_duration_s = 15.0; % hard cap

% Padding around each trial
cfg.pre_pad_s = 0.15;
cfg.post_pad_s = 0.15;

% Preview before committing
cfg.preview_seconds = 10.0;  % play this much of Trial 1 for confirmation

% Optional: auto open Praat so you can read the beep time
cfg.open_praat = true;
% cfg.praat_path = 'C:\Program Files\Praat\Praat.exe';  % if needed on Windows
%%

fprintf('\n=== DAF audio splitter (beep ↔ trials.tsv) ===\n');

% Resolve audio path
if isfolder(cfg.audio_path)
    d = dir(fullfile(cfg.audio_path, '*.wav'));
    assert(~isempty(d), 'No .wav files found in folder: %s', cfg.audio_path);
    [~,ix] = max([d.bytes]);  % pick largest
    cfg.audio_path = fullfile(d(ix).folder, d(ix).name);
    fprintf('Auto-selected audio: %s\n', cfg.audio_path);
end
assert(isfile(cfg.audio_path),  'Audio not found: %s',  cfg.audio_path);
assert(isfile(cfg.trials_path), 'Trials TSV not found: %s', cfg.trials_path);

% Load audio
[x, fs] = audioread(cfg.audio_path);
[nSamps, nCh] = size(x);
durTot  = nSamps / fs;
fprintf('Loaded audio: %s  [%.2f s, %d channel(s)]\n', cfg.audio_path, durTot, nCh);
assert(cfg.channel_index>=1 && cfg.channel_index<=nCh, ...
    'cfg.channel_index=%d out of range (file has %d channels).', cfg.channel_index, nCh);

% Load trials
T = read_text_table(cfg.trials_path);
T.Properties.VariableNames = lower(strrep(T.Properties.VariableNames, ' ', '_'));

onset_col = '';
if any(strcmp(T.Properties.VariableNames, 'visual_onset_time'))
    onset_col = 'visual_onset_time';
elseif any(strcmp(T.Properties.VariableNames, 'time_visual_on'))
    onset_col = 'time_visual_on';
else
    error('Trials TSV must contain ''visual_onset_time'' or ''time_visual_on'' (seconds).');
end

trial_onsets_task = double(T.(onset_col));
trial_onsets_task = trial_onsets_task(:);
valid_trials = ~isnan(trial_onsets_task);
trial_onsets_task = trial_onsets_task(valid_trials);
assert(~isempty(trial_onsets_task), 'No valid trial onsets in trials.tsv.');
[first_t, idx_first] = min(trial_onsets_task);
fprintf('Detected %d trial start(s). First trial (task clock): %.6f s\n', numel(trial_onsets_task), first_t);

% Open Praat (optional)
if cfg.open_praat
    if ismac
        system(sprintf('open -a Praat "%s"', cfg.audio_path));
    elseif ispc
        if isfield(cfg,'praat_path') && ~isempty(cfg.praat_path)
            praatExe = cfg.praat_path;
        else
            cand = {fullfile(getenv('ProgramFiles'),'Praat','Praat.exe'), ...
                    fullfile(getenv('ProgramFiles(x86)'),'Praat','Praat.exe')};
            praatExe = '';
            for k=1:numel(cand), if exist(cand{k},'file'), praatExe=cand{k}; break; end, end
            if isempty(praatExe), praatExe = 'Praat.exe'; end
        end
        system(sprintf('"%s" "%s"', praatExe, cfg.audio_path));
    else
        fprintf('Open this file in Praat manually:\n  %s\n', cfg.audio_path);
    end
end

% Get AUDIO beep time
beep_onset_audio = str2double(input( ...
    'Enter FIRST BEEP time IN THE AUDIO (seconds from 0, as seen in Praat): ','s'));
assert(~isnan(beep_onset_audio) && beep_onset_audio>=0 && beep_onset_audio<=durTot, ...
    'Invalid audio beep time.');

% Alignment
offset_s = beep_onset_audio - first_t;
starts_audio = trial_onsets_task + offset_s;

fprintf('Alignment offset = %.6f s  (audio_time = trials_time + %.6f)\n', offset_s, offset_s);

% warn if out of range
if any(starts_audio < -5 | starts_audio > durTot+5)
    warning(['Some computed trial starts fall outside the audio range. ', ...
             'Check your beep time or confirm trials file. Example: %.3f s'], ...
             starts_audio(find(starts_audio<-5 | starts_audio>durTot+5,1,'first')));
end

%%
% End times per trial
if cfg.use_next_onset
    ends_audio = zeros(size(starts_audio));
    for i = 1:numel(starts_audio)
        if i < numel(starts_audio)
            ends_audio(i) = min(starts_audio(i) + cfg.max_duration_s, ...
                                starts_audio(i+1) - cfg.boundary_guard_s);
        else
            ends_audio(i) = min(starts_audio(i) + cfg.max_duration_s, durTot);
        end
    end
else
    ends_audio = starts_audio + cfg.trial_duration_s;
end

% Apply padding & clamp
starts_audio = max(0, starts_audio - cfg.pre_pad_s);
ends_audio   = min(durTot, ends_audio + cfg.post_pad_s);

% To samples
starts_samp = max(1, floor(starts_audio * fs) + 1);
ends_samp   = min(nSamps, ceil(ends_audio * fs));
valid_len   = ends_samp > starts_samp;
assert(any(valid_len), 'No valid trial segments after alignment—check beep time.');

%%
% Preview T1
i1 = find(valid_len, 1, 'first');
s1 = starts_samp(i1); e1 = min(nSamps, s1 + round(cfg.preview_seconds*fs) - 1);
fprintf('\nPlaying %.2f s of Trial 1 (channel %d) for confirmation...\n', (e1-s1+1)/fs, cfg.channel_index);
sound(x(s1:e1, cfg.channel_index), fs);
resp = lower(strtrim(input('Does that sound like the correct trial? (y/n): ','s')));
if ~strcmp(resp,'y')
    fprintf('Aborted by user. Re-run with corrected beep time or channel index.\n');
    return
end

%%
% Export WAVs
if ~exist(cfg.output_dir, 'dir'); mkdir(cfg.output_dir); end
manifest = table('Size',[0 9], 'VariableTypes', ...
    {'double','double','double','double','double','string','double','double','double'}, ...
    'VariableNames', {'trial','start_s','end_s','start_sample','end_sample','filename', ...
                      'beep_audio_s','offset_s','fs'});

trial_idx = 0;
for i = 1:numel(starts_samp)
    if ~valid_len(i), continue; end
    trial_idx = trial_idx + 1;

    y = x(starts_samp(i):ends_samp(i), cfg.channel_index);  % single-channel export
    fname = sprintf('trial_%03d.wav', trial_idx);
    audiowrite(fullfile(cfg.output_dir, fname), y, fs);

    manifest = [manifest; { ...
        trial_idx, starts_audio(i), ends_audio(i), ...
        starts_samp(i), ends_samp(i), string(fname), ...
        beep_onset_audio, offset_s, fs}];
end

writetable(manifest, fullfile(cfg.output_dir, 'manifest.csv'));

fprintf('\nExport complete.\n  Trials written : %d\n  Folder        : %s\n  Manifest      : %s\n  Channel       : %d / %d\n  Beep (audio)  : %.6f s\n  Offset        : %.6f s\n\n', ...
    height(manifest), cfg.output_dir, fullfile(cfg.output_dir, 'manifest.csv'), ...
    cfg.channel_index, nCh, beep_onset_audio, offset_s);

%% helper
function T = read_text_table(p)
    [~,~,ext] = fileparts(p);
    switch lower(ext)
        case {'.tsv','.txt'}
            opts = detectImportOptions(p, 'FileType','text', 'Delimiter','\t');
        otherwise
            opts = detectImportOptions(p, 'FileType','text'); % CSV default
    end
    T = readtable(p, opts);
end