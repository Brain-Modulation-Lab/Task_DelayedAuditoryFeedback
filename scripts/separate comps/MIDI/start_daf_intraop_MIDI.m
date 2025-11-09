function start_daf_intraop_MIDI
% start_daf_intraop_MIDI - Intraoperative launcher for the Delayed Auditory Feedback (DAF) task
%
% This function configures and launches task_daf_MIDI, which controls
% the experiment presentation, timing, and communication with the H90 Eventide.
% It sets default parameters, prepares paths and logging filenames, initializes
% optional audio recording and hardware interfaces, and launches the task script.
%
% No input arguments; all configuration is inside the function.
%
% The configuration is stored in the 'cfg' struct, passed to the task function.

%% Setup experiment configuration
cfg = struct();
cfg.SESSION_LABEL = 'intraop';      % Label for session type (e.g., intraop, preop)
cfg.SUBJECT       = 'daftestsub';   % Subject identifier
cfg.DATA_TYPE     = 'task';         % Data type for folder structure
cfg.RECORD_AUDIO  = false;          % Whether to record microphone audio during the task
cfg.LagMetrics    = false;          % Whether to enable lag metrics
cfg.PTB           = false;          % Use Psychtoolbox for timing and display (false disables it)
cfg.STOP_BETWEEN_TRIALS = true;     % Require space to proceed between all trials (after ITI plays)
cfg.ALWAYS_ON_0MS = true;           % Plays audio back through headphones throughout experiment

% Task metadata
cfg.TASK          = 'daf';              % Task name
cfg.TASK_VERSION  = 1;                  % Version number
cfg.TASK_FUNCTION = 'task_daf_MIDI.m';  % Task main function filename

% Core DAF parameters
cfg.max_trials             = inf;     % Maximum number of trials (inf = unlimited)
cfg.audio_sample_rate      = 44100;   % Audio sample rate (Hz)
cfg.audio_frame_size       = 60;      % Audio frame size for buffer processing
cfg.audio_playback_gain    = 0.1;     % Output audio gain (volume)
cfg.fix_cross_dur          = 0.0;     % Duration to show fixation cross (seconds)
cfg.text_stim_dur          = 10;      % Duration to show text stimulus on screen (seconds)
cfg.stim_font_size         = 50;      % Font size of stimulus text
cfg.stim_max_char_per_line = 30;      % Maximum characters per line in stimulus text
cfg.catchRatio             = 0;       % Probability of catch trials (no auditory feedback)
cfg.max_stim_repeats       = 2;       % Max number of repeats per stimulus
cfg.max_delay_repeats      = 4;       % Max repeats per delay condition
cfg.same_trials_across_blocks = true; % Use same trials repeated across blocks
cfg.maxAllowedDelay_ms = 1000;        % Maximum allowed DAF delay (ms)
cfg.DAF_START_OFFSET_S = 0.000;       % Optional time offset between fixation and DAF start 

% Stimulus sentences file per session
cfg.daf_stim_file = ['daf_sentences_extra_alliteration' cfg.SESSION_LABEL '.tsv'];

% Set delay values and number of blocks according to session type
switch cfg.SESSION_LABEL
    case 'preop'
        cfg.delay_values_ms = [0 100 150 200 250];
        cfg.n_blocks = 2;
    case 'intraop'
        cfg.delay_values_ms = [0 100];
        cfg.n_blocks = 4;
    otherwise
        error('Unknown session label: %s', cfg.SESSION_LABEL);
end
if any(cfg.delay_values_ms > cfg.maxAllowedDelay_ms) % Validate that delay values do not exceed maximum allowed delay
    error('One or more delay options exceed max %d ms.', cfg.maxAllowedDelay_ms);
end

%% MIDI setup
cfg.DAF_CONTROL   = 'midi';
cfg.MIDI_OUT_NAME = 'Eventide H90';
cfg.MIDI_CHANNEL  = 1;                

% get extra piece of hardware for 1ms granularity
% Preset per delay mapping
cfg.USE_PRESETS = true;
delays = int32(round(cfg.delay_values_ms(:)'));            % row vector of int32
presetNums = num2cell(1:numel(delays));
cfg.PRESET_MAP = containers.Map(num2cell(delays), presetNums);

% Ensure all delays have a preset
assert(all(isKey(cfg.PRESET_MAP, num2cell(cfg.delay_values_ms))), 'PRESET_MAP must cover all delay_values_ms.');

%% PTB optional setup
usePTB = false;
if isfield(cfg,'PTB')
    if islogical(cfg.PTB), usePTB = cfg.PTB;
    elseif ischar(cfg.PTB) || isstring(cfg.PTB)
        usePTB = any(strcmpi(string(cfg.PTB), ["true","on","ptb","1"]));
    end
end
fprintf('[Starter] PTB backend requested: %d\n', usePTB);

if usePTB && exist('Screen','file')>0 % Enable all warnings, disable beeps, setup Psychtoolbox preferences for timing
    warning('on', 'all');
    beep off;
    PsychDefaultSetup(2);
    Screen('Preference', 'SkipSyncTests', 1);
    Screen('Preference', 'ConserveVRAM', 4096);
    Screen('Preference', 'VisualDebugLevel', 1);
    Screen('Preference', 'Verbosity', 3);
    PsychDebugWindowConfiguration;
end

%% Parallel pool for optional audio recording (master)
if cfg.RECORD_AUDIO && isempty(gcp('nocreate'))
    parpool('local',1);
end
if cfg.RECORD_AUDIO
    workerQueue = parallel.pool.PollableDataQueue;
    workerQueueConstant = parallel.pool.Constant(workerQueue);
end

%% Paths & output folders
if strcmpi(getenv('COMPUTERNAME'), 'BML-ALIENWARE2')
    cfg.PATH_TASK       = 'D:\Task\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata';
elseif ismac
    cfg.PATH_TASK       = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/';
    cfg.PATH_SOURCEDATA = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/stimuli';
else
    cfg.PATH_TASK       = '~/git/Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata';
end

% Build subject/session level folders for data storage
pathSub = fullfile(cfg.PATH_SOURCEDATA, ['sub-' cfg.SUBJECT]);
pathSubSes = fullfile(pathSub, ['ses-' cfg.SESSION_LABEL]);
pathSubSesDataType = fullfile(pathSubSes, cfg.DATA_TYPE);
pathSubSesAudio = fullfile(pathSubSes, 'audio');

% Create output directories if they do not exist
for p = {cfg.PATH_SOURCEDATA, pathSub, pathSubSes, pathSubSesDataType, pathSubSesAudio}
    if ~isfolder(p{1}), mkdir(p{1}); end
end
cfg.PATH_AUDIO = pathSubSesAudio;

%% Run basename, filenames
fileBaseName  = ['sub-' cfg.SUBJECT '_ses-' cfg.SESSION_LABEL '_task-' cfg.TASK '_run-'];

% Check existing event files to increment run ID for this session
allEventFiles = dir(fullfile(pathSubSesDataType, [fileBaseName '*_events.tsv']));
if ~isempty(allEventFiles)
    prevRunIds = regexp({allEventFiles.name}, '_run-(\d+)_', 'tokens', 'ignorecase');
    prevRunIds = cellfun(@(x) str2double(x{1,1}), prevRunIds, 'UniformOutput', true);
    runId = max(prevRunIds) + 1;
else
    runId = 1;
end

% Assign run ID and generate file paths for logs and audio
cfg.RUN_ID = runId;
cfg.PATH_LOG = pathSubSesDataType;
cfg.BASE_NAME = [fileBaseName, sprintf('%02d_', runId)];
cfg.LOG_FILENAME = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'log.txt']);
cfg.EVENT_FILENAME = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'events.tsv']);
cfg.TRIAL_FILENAME = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'trials.tsv']);
cfg.AUDIO_FILENAME = fullfile(cfg.PATH_AUDIO, [cfg.BASE_NAME(1:end-1) '.wav']);

%% Start MATLAB diary for logging console output to log file
diary(cfg.LOG_FILENAME);
oc = onCleanup(@() diary('off')); % Ensure diary is turned off when function exits
disp(cfg);  % Display config for verification

%% Change to scripts folder
scriptPath = fullfile(cfg.PATH_TASK, 'scripts');
if ~isfolder(scriptPath)
    error('Scripts folder not found: %s', scriptPath);
end
cd(scriptPath);

%% Start audio recording (optional)
if cfg.RECORD_AUDIO
    if ~(exist('record_audio','file')==2)
        error('record_audio() not found on path.');
    end
    future = parfeval(@record_audio, 1, cfg.AUDIO_FILENAME, workerQueueConstant); % Launch async audio recording task with queue for communication
    future.Diary;
    recCleanup = onCleanup(@() send(workerQueue, 'stop'));
end

%% Ripple neurophysiology hardware communication setup (optional)
cfg.DIGOUT = 0;
if exist('xippmex','file')==3
    try
        digout = xippmex();  % Initialize hardware interface
        cfg.DIGOUT = digout ~=0;
        xippmexCleanup = onCleanup(@() xippmex('close'));
    catch err
        warning('xippmex init failed: %s', err.MESSAGE);
    end
end

%% Open MIDI output
try
    devs = mididevinfo;
catch
    error(['mididevinfo not found. Ensure MATLAB supports MIDI on this installation ', ...
           '(R2020b+ Instrument Control Toolbox or Audio Toolbox w/ MIDI).']);
end
outNames = string({devs.output.Name});
ix = find(contains(lower(outNames), lower(cfg.MIDI_OUT_NAME), 'IgnoreCase', true), 1);
if isempty(ix)
    warning('MIDI out "%s" not found. Available: %s', cfg.MIDI_OUT_NAME, strjoin(outNames, ', '));
    cfg.DAF_MIDI = []; % allow visuals only fallback
else
    cfg.DAF_MIDI = mididevice('Output', outNames(ix));
end

% Log a quick probe for audit
fprintf('[MIDI] Outputs available:\n');
for i = 1:numel(outNames)
    sel = "";
    if i == ix, sel = "  [SELECTED]"; end
    fprintf('  - %s%s\n', outNames(i), sel);
end
if isempty(cfg.DAF_MIDI)
    warning('Running WITHOUT DAF (no MIDI device). Visuals/logging only.');
end

%% Launch task
fprintf('Launching task\n');
task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function)
    error('%s not found in current folder', cfg.TASK_FUNCTION);
end
copyfile(task_function, [cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']); % Copy the task function file to the log folder for reproducibility
feval(strrep(cfg.TASK_FUNCTION,'.m',''), cfg); % Execute the task function, passing full config struct

close all;
end