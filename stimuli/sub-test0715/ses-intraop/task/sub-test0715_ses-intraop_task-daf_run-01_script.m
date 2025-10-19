function task_daf_nonptb(cfg)
% Non-PTB DAF task that preserves functionality & timing of PTB script.
% - Uses MATLAB Audio Toolbox for I/O (audioDeviceReader/Writer)
% - Uses MATLAB figures/text for visuals
% - Keeps BIDS-style logging via log_event()
% - Adds DAF On/Off event logs to mirror PTB behavior
% - Per-trial lag_mean captured when LAG_DIAGNOSTICS enabled
% - Short ~30 ms prefill at trial start (avoids long flush loops)

%%%% run delayed auditory feedback task; in or out of operating room
% by Sam Hansen (SH), Andrew Meier (AM); adapted from other Brain Modulation Lab (BML) scripts
% this variant written to avoid Psychtoolbox audio/visual backends

%% Task specific parameters
ITI_S = [1.75, 2.25]; % duration range in seconds of ITI
TRIG_ITI    = 1;      % Fixation/Trial onset
TRIG_VISUAL = 2;      % Visual on/off
TRIG_DAF    = 4;      % DAF on/off
TRIG_KEY    = 8;      % Escape key

%% Trial table
[cfg, trials] = create_trials_table(cfg);

%% Initializing log files
eventFile = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n'); % BIDS events header

%% Hardware setup (console messages preserved)
fprintf('Initializing non-PTB at %s for subject %s, %s task, session %s, run %i\n\n', ...
    datestr(now,'HH:mm:ss'), cfg.SUBJECT, cfg.TASK, cfg.SESSION_LABEL, cfg.RUN_ID);

% Keyboard setup (kept for parity with PTB semantics)
KbName('UnifyKeyNames');
ESC    = KbName('ESCAPE');
device = []; % default keyboard
ListenChar(0);
ShowCursor;

fprintf('Initializing Keyboard...');
if isempty(cfg.KEYBOARD_ID)
    fprintf('\nNo keyboard selected, using default. Choose KEYBOARD_ID from this table:\n');
    if ~cfg.LOCAL_TEST
        devices = struct2table(PsychHID('Devices')); %#ok<NASGU> (display only)
    else
        devices = table(); %#ok<NASGU>
        fprintf('Skipping PsychHID device enumeration for local test mode.\n');
    end
    % disp(devices); % Uncomment if needed interactively
end

%% Audio setup (MATLAB Audio System Toolbox)
% List input devices
input_devices = getAudioDevices(audioDeviceReader);
for k = 1:length(input_devices)
    fprintf('%d: %s\n', k, input_devices{k});
end
inIdx = input('INPUT device #: ');

% Host-specific input selection (Focusrite on OR laptop)
if ispc
    [~,host] = system('hostname'); host = deblank(host);
elseif ismac
    [~,host] = system('scutil --get LocalHostName'); host = deblank(host);
else
    host = '';
end

if strcmp(host,'BML-ALIENWARE2')
    reader = audioDeviceReader('SampleRate', cfg.audio_sample_rate, ...
        'SamplesPerFrame', cfg.audio_frame_size, ...
        'Device', 'Focusrite USB ASIO', 'Driver','ASIO');
else
    reader = audioDeviceReader('SampleRate', cfg.audio_sample_rate, ...
        'SamplesPerFrame', cfg.audio_frame_size, ...
        'Device', input_devices{inIdx});
end

% List output devices
output_devices = getAudioDevices(audioDeviceWriter);
for k = 1:length(output_devices)
    fprintf('%d: %s\n', k, output_devices{k});
end
outIdx = input('OUTPUT device #: ');

writer = audioDeviceWriter('SampleRate', cfg.audio_sample_rate, ...
                           'Device', output_devices{outIdx});

% VFD capacity must cover maximum configured delay in SAMPLES
maxDelaySamples = ceil(max(cfg.delay_values_ms) * cfg.audio_sample_rate / 1000);
vfd = dsp.VariableFractionalDelay('MaximumDelay', max(maxDelaySamples, round(cfg.audio_sample_rate)));

% Prime audio pipeline (avoid first-buffer glitches)
for k = 1:10, writer(reader()); end

% Convenience vars for per-trial prefill & tail
prefillSamples = round(0.03 * cfg.audio_sample_rate); % ~30 ms
tailSamples    = round(0.02 * cfg.audio_sample_rate); % ~20 ms

%% Visual setup (figure-based, PTB-free)
screenSize = get(0, 'ScreenSize');
fig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', ...
             'Position',[screenSize(3)/4 screenSize(4)/4 900 600], 'NumberTitle','off');
ax = axes('Parent',fig,'Position',[0 0 1 1],'Visible','off');
hText = text(0.5, 0.5, '', 'FontSize', cfg.stim_font_size, 'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','middle','Units','normalized','Parent', ax);

stopFig = figure('Name','Stop','NumberTitle','off','MenuBar','none','ToolBar','none','Position',[300 100 200 80]);
setappdata(0, 'stopReq', false);
uicontrol(stopFig,'Style','pushbutton','String','Stop','FontSize',14,'Position',[50 20 100 40], ...
    'Callback', @(~,~) setappdata(0,'stopReq',true));

%% Instructions and sync beeps (PTB-like timing)
instructions = ['INSTRUCTIONS\n\n' 'When text appears on the screen,\n' ...
                'Read as quickly and accurately as possible.\n\n' ...
                'Press any key to begin...'];
set(hText, 'String', sprintf(instructions), 'FontSize', 55, 'Color', 'black'); drawnow;
figure(fig);
instrOn = GetSecs(); % mirror PTB "flip timestamp" semantics
set(fig, 'WindowKeyPressFcn', @(~,~) uiresume(fig));
uiwait(fig);
set(fig, 'WindowKeyPressFcn', '');
set(hText, 'String', ''); drawnow;

% 3 sync beeps + "SYNC" text, same cadence
beepWave = 0.1 * sin(2*pi*1000*(0:1/cfg.audio_sample_rate:0.2));
set(hText, 'String', 'SYNC', 'FontSize', 48, 'Color', 'red'); drawnow;
for i = 1:3
    if i == 1, refTime = GetSecs; end %#ok<NASGU>
    sound(beepWave, cfg.audio_sample_rate);
    pause(0.5);
end
set(hText, 'String', ''); drawnow;

% Keyboard queue (low-latency key detection)
KbQueueCreate(device);
KbQueueStart(device);

% Timing bases for absolute datetime stamps
baseGetSecs = GetSecs();
baseClock   = datetime('now','TimeZone','local');

% Log the instructions event
flipSyncState = 0;
flipSyncState = ~flipSyncState;
log_event(eventFile, 0, instrOn, [], [], [], [], 0, 'Instructions', flipSyncState);

%% Trial loop (functionally mirrors PTB)
runStartTime = GetSecs();
speechVsCatch = '';
goto_cleanup  = false;

% Lag diagnostics globals (per-trial mean written to trials.lag_mean)
doSoftLag = isfield(cfg,'LAG_DIAGNOSTICS') && cfg.LAG_DIAGNOSTICS && ~cfg.LOCAL_TEST;
lagBuffer = zeros(1, 5000); lagIndex = 1; lagCount = 0;

for itrial = 1:cfg.ntrials
    % Global ESC abort check
    [isDown, ~, kc] = KbQueueCheck(device);
    if isDown && kc(ESC)
        flipSyncState = ~flipSyncState;
        log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], speechVsCatch, [], TRIG_KEY, 'Escape/Stop', flipSyncState);
        goto_cleanup = true; break;
    end

    % Trial type (catch vs speech) + cue color
    if trials.catch_trial(itrial)
        speechVsCatch = 'catch';
        fixColor = 'red';
    else
        speechVsCatch = 'speech';
        fixColor = [0 0 0];
    end

    % Trial delay (samples)
    delay_samples = cfg.audio_sample_rate * trials.delay(itrial) / 1000;

    % Short prefill + reset VFD (instead of long multi-frame flush)
    writer(zeros(prefillSamples,1));
    reset(vfd);

    % ITI fixation cue (asterisk), log Trial Onset
    set(hText, 'String', '*', 'FontSize', cfg.stim_font_size, 'Color', ifelse(~trials.catch_trial(itrial), [0.7 0.7 0.7], 'red'));
    drawnow;
    itiFixOnTime = GetSecs();
    trials.start_time(itrial) = baseClock + seconds(itiFixOnTime - baseGetSecs);
    flipSyncState = ~flipSyncState;
    ItiDuration = ITI_S(1) + (ITI_S(2) - ITI_S(1)) * rand(1);
    log_event(eventFile, cfg.DIGOUT, itiFixOnTime, ItiDuration, [], speechVsCatch, [], TRIG_ITI, 'Trial Onset', flipSyncState);

    % ITI dwell with ESC check
    tEnd = itiFixOnTime + ItiDuration;
    while GetSecs < tEnd
        [isDown, ~, kc] = KbQueueCheck(device);
        if isDown && kc(ESC)
            flipSyncState = ~flipSyncState;
            log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], speechVsCatch, [], TRIG_ITI + TRIG_KEY, 'Escape/Stop', flipSyncState);
            goto_cleanup = true; break;
        end
        WaitSecs(0.001);
    end
    if goto_cleanup, break; end

    % Pre-stim blank delay (matches PTB pre-stim pause)
    set(hText, 'String', ''); drawnow;
    WaitSecs(cfg.delay_dur);

    % Visual ON (sentence)
    set(hText, 'String', trials.stim{itrial}, 'FontSize', cfg.stim_font_size, 'Color', 'black'); drawnow;
    stimOnsetTime = GetSecs();
    flipSyncState = ~flipSyncState;
    trials.visual_onset_time(itrial) = baseClock + seconds(stimOnsetTime - baseGetSecs);
    log_event(eventFile, cfg.DIGOUT, stimOnsetTime, [], [], speechVsCatch, trials.stim{itrial}, TRIG_VISUAL, 'Visual Onset', flipSyncState);

    % DAF On (mirror PTB: for all SPEECH trials, even 0 ms delay)
    if ~trials.catch_trial(itrial) && ~cfg.LOCAL_TEST
        flipSyncState = ~flipSyncState;
        log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], speechVsCatch, [], TRIG_DAF, 'DAF On', flipSyncState);
    end

    % Streaming loop (speech trials) or passive wait (catch)
    if ~trials.catch_trial(itrial) && ~cfg.LOCAL_TEST
        KbQueueFlush(device);
        trialStart = GetSecs();
        % reset per-trial lag stats
        lagIndex = 1; lagCount = 0;

        while (GetSecs - trialStart) < cfg.text_stim_dur && ~getappdata(0,'stopReq')
            % Mid-trial ESC check (matches PTB behavior)
            [pressed, fp] = KbQueueCheck(device);
            if pressed && fp(ESC)
                flipSyncState = ~flipSyncState;
                log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], speechVsCatch, [], TRIG_KEY, 'Escape/Stop', flipSyncState);
                goto_cleanup = true; break;
            end

            tStart  = GetSecs;
            audioIn = reader();
            delayed = vfd(audioIn, delay_samples);
            audioOut = max(min(cfg.audio_playback_gain * delayed, 1), -1);
            writer(audioOut);

            if doSoftLag
                proc_ms = (GetSecs - tStart) * 1000;
                frame_ms = (cfg.audio_frame_size / cfg.audio_sample_rate) * 1000;
                lag = max(proc_ms - frame_ms, 0);
                lagBuffer(lagIndex) = lag;
                lagIndex = mod(lagIndex, numel(lagBuffer)) + 1;
                lagCount = min(lagCount+1, numel(lagBuffer));
            end

            % Light GUI servicing at ~100 Hz cap
            pause(0.001);
        end

        % Short tail to flush residual & reset VFD
        writer(zeros(tailSamples,1));
        reset(vfd);

        % Per-trial lag mean
        if doSoftLag && lagCount > 0
            trials.lag_mean(itrial) = mean(lagBuffer(1:lagCount));
        else
            trials.lag_mean(itrial) = NaN;
        end

        if goto_cleanup, break; end
    else
        % Catch or local test: passive wait with ESC check
        t0 = GetSecs();
        while (GetSecs - t0) < cfg.text_stim_dur
            [isDown, ~, kc] = KbQueueCheck(device);
            if isDown && kc(ESC)
                flipSyncState = ~flipSyncState;
                log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], speechVsCatch, [], TRIG_KEY, 'Escape/Stop', flipSyncState);
                goto_cleanup = true; break;
            end
            WaitSecs(0.005);
        end
        if goto_cleanup, break; end
    end

    % DAF Off (speech trials only)
    if ~trials.catch_trial(itrial) && ~cfg.LOCAL_TEST
        flipSyncState = ~flipSyncState;
        log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], speechVsCatch, [], TRIG_DAF, 'DAF Off', flipSyncState);
    end

    % Visual OFF
    set(hText, 'String', ''); drawnow;
    visOffTime = GetSecs();
    flipSyncState = ~flipSyncState;
    trials.visual_off_time(itrial) = baseClock + seconds(visOffTime - baseGetSecs);
    log_event(eventFile, cfg.DIGOUT, visOffTime, [], [], speechVsCatch, [], TRIG_VISUAL, 'Visual Off', flipSyncState);

    % Console progress
    elapsed = GetSecs() - runStartTime;
    fprintf('Trial %2i / %i completed at %02d:%02d \n', itrial, cfg.ntrials, floor(elapsed/60), round(mod(elapsed,60)));

    % Incremental trials.tsv write
    if itrial == 1
        writetable(trials(1,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteVariableNames', true);
    else
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteMode', 'append', 'WriteVariableNames', false);
    end
end

%% Cleanup section: final log + resource release
flipSyncState = ~flipSyncState;
log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], [], [], 0, 'End Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n', ...
    cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));
fprintf('RUN ID: %i\n',cfg.RUN_ID);

% Release hardware & close windows
release(reader);
release(writer);
release(vfd);
try close(fig);     catch, end
try close(stopFig); catch, end

% Keyboard & misc
try KbQueueRelease(device); catch, end
try ListenChar(0);          catch, end
try ShowCursor;             catch, end
try Priority(0);            catch, end

% Close the event file safely
try fclose(eventFile);      catch, end

end

%% Helper: ternary-like
function out = ifelse(cond, a, b)
    if cond, out = a; else, out = b; end
end