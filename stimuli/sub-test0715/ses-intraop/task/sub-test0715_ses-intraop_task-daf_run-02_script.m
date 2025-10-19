function test_task(cfg)
% Non-PTB DAF task: preserves original functionality using MATLAB/Audio Toolbox only.

%%%% run delayed auditory feedback task; in or out of operating room
% by Sam Hansen (SH), Andrew Meier (AM); adapted from other Brain Modulation Lab (BML) scripts

%% Task specific parameters
% Fixation Cross ITI parameters
ITI_S = [1.75, 2.25]; % duration range in seconds of ITI

% Trigger codes for event marking
TRIG_ITI    = 1; % Trigger for start of ITI
TRIG_VISUAL = 2; % Visual stimulus onset/offset
TRIG_DAF    = 4; % Delayed auditory feedback on/off
TRIG_KEY    = 8; % Keyboard escape key press

%% Trial table
[cfg, trials] = create_trials_table(cfg);

%% Initializing log files
eventFile = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n'); % BIDS event file

%% Hardware/setup banner
fprintf('Initializing (non-PTB) at %s for subject %s, %s task, session %s, run %i\n\n', ...
    datestr(now,'HH:mm:ss'), cfg.SUBJECT, cfg.TASK, cfg.SESSION_LABEL, cfg.RUN_ID);

%% --- MATLAB-only timing helpers (replace PTB GetSecs/WaitSecs) ---
t0 = tic;                         % reference start for monotonic time
now_secs = @() toc(t0);           % seconds since start (double)
sleep_s  = @(s) pause(max(s,0));  % simple sleep in seconds

%% Audio setup (Audio Toolbox)
% List available audio input devices
input_devices = getAudioDevices(audioDeviceReader);
for k = 1:length(input_devices)
    fprintf('%d: %s\n', k, input_devices{k});
end
inIdx = input('INPUT device #: ');

% Choose device/driver depending on host
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
        'Device', 'Focusrite USB ASIO', ...
        'Driver','ASIO'); % Live mic input (ASIO)
else
    reader = audioDeviceReader('SampleRate', cfg.audio_sample_rate, ...
        'SamplesPerFrame', cfg.audio_frame_size, ...
        'Device', input_devices{inIdx});
end

% Output devices
output_devices = getAudioDevices(audioDeviceWriter);
for k = 1:length(output_devices)
    fprintf('%d: %s\n', k, output_devices{k});
end
outIdx = input('OUTPUT device #: ');

writer = audioDeviceWriter('SampleRate', cfg.audio_sample_rate, 'Device', output_devices{outIdx});
vfd    = dsp.VariableFractionalDelay('MaximumDelay', round(cfg.audio_sample_rate));

% Prime audio pipeline
for k = 1:10, writer(reader()); end

maxDelay_ms    = max(cfg.delay_values_ms);
maxDelayFrames = ceil((maxDelay_ms/1000) * cfg.audio_sample_rate / cfg.audio_frame_size) + 5;

%% Visuals (MATLAB graphics)
screenSize = get(0, 'ScreenSize');
fig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', ...
             'Position',[screenSize(3)/4 screenSize(4)/4 900 600],'NumberTitle','off');
ax = axes('Parent',fig,'Position',[0 0 1 1],'Visible','off');
hText = text(0.5, 0.5, '', 'FontSize', cfg.stim_font_size, 'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','middle','Units','normalized','Parent', ax);

% Stop button window (kept from previous non-PTB versions)
stopFig = figure('Name','Stop','NumberTitle','off','MenuBar','none','ToolBar','none','Position',[300 100 200 80]);
setappdata(0, 'stopReq', false);
uicontrol(stopFig,'Style','pushbutton','String','Stop','FontSize',14,'Position',[50 20 100 40], ...
    'Callback', @(~,~) setappdata(0,'stopReq',true));

% Figure-based ESC handling (no PsychHID)
setappdata(fig, 'escPressed', false);
set(fig, 'WindowKeyPressFcn', @(~,evt) setappdata(fig,'escPressed', strcmp(evt.Key,'escape')));

%% Instructions and sync beeps (PTB-free)
instructions = ['INSTRUCTIONS\n\n' 'When text appears on the screen,\n' ...
                'Read as quickly and accurately as possible.\n\n' 'Press any key to begin...'];
set(hText, 'String', sprintf(instructions), 'FontSize', 55, 'Color', 'black');
figure(fig);
instrOn = now_secs();

% Temporarily override keypress to resume on any key
prevHandler = get(fig, 'WindowKeyPressFcn');
set(fig, 'WindowKeyPressFcn', @(~,~) uiresume(fig));
uiwait(fig);
set(fig, 'WindowKeyPressFcn', prevHandler);

set(hText, 'String', ''); drawnow;
beepWave = 0.1 * sin(2*pi*1000*(0:1/cfg.audio_sample_rate:0.2));
set(hText, 'String', 'SYNC', 'FontSize', 48, 'Color', 'red'); drawnow;
for i = 1:3
    if i == 1
        refTime = now_secs(); % experiment zero
    end
    sound(beepWave, cfg.audio_sample_rate);
    pause(0.5);
end
set(hText, 'String', ''); drawnow;

% Initialize clocks for event timing
baseGetSecs = refTime; % same units as now_secs()
baseClock   = datetime('now','TimeZone','local');

% Log instruction onset (use our monotonic seconds)
flipSyncState = 0;
flipSyncState = ~flipSyncState;
log_event(eventFile, 0, instrOn, [], [], [], [], 0, 'Instructions', flipSyncState);

%% Trial Loop main
runStartTime = now_secs();
speechVsCatch = '';
goto_cleanup  = false;

% Lag diagnostics buffer (kept for parity)
doSoftLag   = isfield(cfg,'LAG_DIAGNOSTICS') && cfg.LAG_DIAGNOSTICS && ~cfg.LOCAL_TEST;
lagBuffer   = zeros(1, 5000);
lagIndex    = 1;
lagCount    = 0;

for itrial = 1:cfg.ntrials
    % ESC check (figure handler) or Stop button
    if getappdata(fig,'escPressed')
        flipSyncState = ~flipSyncState;
        log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], speechVsCatch, [], TRIG_KEY, 'Escape/Stop', flipSyncState);
        goto_cleanup = true; break;
    end
    if getappdata(0,'stopReq')
        flipSyncState = ~flipSyncState;
        log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], speechVsCatch, [], TRIG_KEY, 'Stop Button', flipSyncState);
        goto_cleanup = true; break;
    end

    % Trial type (catch vs speech) and fixation color
    if trials.catch_trial(itrial)
        speechVsCatch = 'catch';
        fixColor = [255 0 0];
    else
        speechVsCatch = 'speech';
        fixColor = [0 0 0];
    end

    delay_samples = round(cfg.audio_sample_rate * trials.delay(itrial) / 1000);

    % Flush audio path a few frames then reset delay
    for iframe = 1:maxDelayFrames
        writer(zeros(cfg.audio_frame_size,1));
        vfd(zeros(cfg.audio_frame_size,1), delay_samples);
    end
    reset(vfd);

    % Diagnostic print
    fprintf('Starting trial %d with stim index %d and delay %d ms\n', ...
        itrial, trials.stim_idx(itrial), trials.delay(itrial));

    % ITI with fixation "cross" (asterisk here) and log
    set(hText, 'String', '*', 'FontSize', cfg.stim_font_size, ...
        'Color', ifelse(~trials.catch_trial(itrial), [0.7 0.7 0.7], 'red'));
    drawnow;
    itiFixOnTime = now_secs();
    trials.fix_time(itrial) = baseClock + seconds(itiFixOnTime - baseGetSecs);

    flipSyncState = ~flipSyncState;
    ItiDuration   = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);
    log_event(eventFile, cfg.DIGOUT, itiFixOnTime, ItiDuration, [], speechVsCatch, [], TRIG_ITI, 'Fixation_Cross_Onset', flipSyncState);

    % ITI wait loop (ESC/Stop responsive)
    tEnd = itiFixOnTime + ItiDuration;
    while now_secs() < tEnd
        if getappdata(fig,'escPressed')
            flipSyncState = ~flipSyncState;
            log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], speechVsCatch, [], TRIG_ITI + TRIG_KEY, 'Escape/Stop', flipSyncState);
            goto_cleanup = true; break;
        end
        if getappdata(0,'stopReq')
            flipSyncState = ~flipSyncState;
            log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], speechVsCatch, [], TRIG_ITI + TRIG_KEY, 'Stop Button', flipSyncState);
            goto_cleanup = true; break;
        end
        sleep_s(0.005);
    end
    if goto_cleanup, break; end

    % Pre-stim delay
    sleep_s(cfg.delay_dur);

    % Visual stimulus on
    set(hText, 'String', trials.stim{itrial}, 'FontSize', cfg.stim_font_size, 'Color', 'black');
    drawnow;
    stimOnsetTime = now_secs();
    flipSyncState = ~flipSyncState;
    trials.visual_onset_time(itrial) = baseClock + seconds(stimOnsetTime - baseGetSecs);
    text_stim = trials.stim{itrial};
    log_event(eventFile, cfg.DIGOUT, stimOnsetTime, [], [], speechVsCatch, text_stim, TRIG_VISUAL, 'Visual Onset', flipSyncState);

    % Streaming Loop: mic -> fractional delay -> speakers
    if ~trials.catch_trial(itrial) && ~cfg.LOCAL_TEST
        trialStart   = now_secs();
        frameCounter = 0;

        while (now_secs() - trialStart) < cfg.text_stim_dur && ...
              ~getappdata(0,'stopReq') && ~getappdata(fig,'escPressed')

            tStart  = now_secs();
            audioIn = reader();
            delayed = vfd(audioIn, delay_samples);
            audioOut= max(min(cfg.audio_playback_gain * delayed, 1), -1);
            writer(audioOut);

            if doSoftLag
                frameDur_ms = (cfg.audio_frame_size/cfg.audio_sample_rate)*1000;
                lag = max((now_secs() - tStart)*1000 - frameDur_ms, 0);
                lagBuffer(lagIndex) = lag;
                lagIndex = mod(lagIndex, 5000) + 1;
                lagCount = min(lagCount+1, 5000);
            end

            frameCounter = frameCounter + 1;
            if mod(frameCounter, 10) == 0
                drawnow;
            end

            pause(0.001); % tame CPU
        end

        % Tail flush
        for iframe = 1:maxDelayFrames
            audioOut = vfd(zeros(cfg.audio_frame_size,1), delay_samples);
            writer(audioOut);
        end
        reset(vfd);
        sleep_s(0.1);
    else
        % Catch or local test: passive wait, ESC/Stop responsive
        t0_local = now_secs();
        while (now_secs() - t0_local) < cfg.text_stim_dur
            if getappdata(fig,'escPressed') || getappdata(0,'stopReq')
                goto_cleanup = true; break;
            end
            sleep_s(0.005);
        end
        if goto_cleanup, break; end
    end

    % DAF off event
    if ~trials.catch_trial(itrial) && ~cfg.LOCAL_TEST
        flipSyncState = ~flipSyncState;
        dafOffTime = now_secs();
        log_event(eventFile, cfg.DIGOUT, dafOffTime, [], [], speechVsCatch, [], TRIG_DAF, 'DAF Off', flipSyncState);
    end

    % Visual off
    set(hText, 'String', ''); drawnow;
    flipSyncState = ~flipSyncState;
    visOffTime = now_secs();
    trials.visual_off_time(itrial) = baseClock + seconds(visOffTime - baseGetSecs);
    log_event(eventFile, cfg.DIGOUT, visOffTime, [], [], speechVsCatch, [], TRIG_VISUAL, 'Visual Off', flipSyncState);

    % Progress print
    elapsed = now_secs() - runStartTime;
    fprintf('Trial %2i / %i completed at %02d:%02d \n', itrial, cfg.ntrials, floor(elapsed/60), round(mod(elapsed,60)));

    % Persist trial row
    if itrial == 1
        writetable(trials(1,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteVariableNames', true);
    else
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteMode', 'append', 'WriteVariableNames', false);
    end
end

%% Cleanup section
flipSyncState = ~flipSyncState;
log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], [], [], 0, 'End Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n', ...
    cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));
fprintf('RUN ID: %i\n',cfg.RUN_ID);

% Release hardware, close windows
try release(reader);  catch, end
try release(writer);  catch, end
try release(vfd);     catch, end
try close(fig);       catch, end
try close(stopFig);   catch, end
try fclose(eventFile);catch, end
rmappdata(0,'stopReq');

end

%% Helper function (Ternary operator: returns a if cond is true, else b)
function out = ifelse(cond, a, b)
    if cond, out = a; else, out = b; end
end
