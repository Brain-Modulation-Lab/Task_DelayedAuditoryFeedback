function testv2(cfg)

%%%% run delayed auditory feedback task; in or out of operating room
% by Sam Hansen (SH), Andrew Meier (AM); adapted from other Brain Modulation Lab (BML) scripts
% PTB-free version: uses MATLAB graphics + Audio System Toolbox + DSP System Toolbox

%% Task specific parameters
% Fixation Cross ITI parameters
ITI_S = [1.75, 2.25]; % duration range in seconds of ITI

% Trigger codes for event marking
TRIG_ITI      = 1;  % Trigger for start of ITI
TRIG_VISUAL   = 2;  % Visual stimulus onset/offset
TRIG_DAF      = 4;  % Delayed auditory feedback on/off
TRIG_KEYPRESS = 8;  % Spacebar keypress (to proceed to next trial)
TRIG_ESC      = 16; % Keyboard escape key press

%% Trial table
[cfg, trials, text_wrapped_all] = create_trials_table(cfg);

%% Initializing log files
eventFile = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n'); % BIDS event file in system time coord

%% Hardware setup (Audio in/out)
fprintf('Initializing PTB-free DAF at %s for subject %s, %s task, session %s, run %i\n\n', ...
    datestr(now,'HH:mm:ss'), cfg.SUBJECT, cfg.TASK, cfg.SESSION_LABEL, cfg.RUN_ID);

if ispc
    [~, host] = system('hostname');
    cfg.host = strtrim(host);
    audio_reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, ...
        'SampleRate', cfg.audio_sample_rate, ...
        'SamplesPerFrame', cfg.audio_frame_size, ...
        'Driver','ASIO'); % adjust to WASAPI if needed
else
    [~, host] = system('scutil --get LocalHostName');
    cfg.host = strtrim(host);
    audio_reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, ...
        'SampleRate', cfg.audio_sample_rate, ...
        'SamplesPerFrame', cfg.audio_frame_size);
end

audio_writer = audioDeviceWriter('Device', cfg.AUDIO_DEVICE_OUT, ...
    'SampleRate', cfg.audio_sample_rate);

vfd = dsp.VariableFractionalDelay('MaximumDelay', round(cfg.audio_sample_rate)); % DAF buffer
for k = 1:10
    try
        audio_writer(audio_reader()); % prime pipeline to avoid startup glitch
    catch
        break
    end
end

maxDelay_ms     = max(cfg.delay_values_ms);
maxDelayFrames  = ceil((maxDelay_ms/1000) * cfg.audio_sample_rate / cfg.audio_frame_size) + 5;

%% Stimulus figure setup (full screen text + photodiode square)
scr = get(0, 'ScreenSize');
hfig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', ...
    'Position', [0 0 scr(3) scr(4)], 'NumberTitle','off', 'Visible','on');
ax = axes('Parent',hfig,'Position',[0 0 1 1],'Visible','off');
hText = text(0.5, 0.5, '', ...
    'FontSize', cfg.stim_font_size, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Units','normalized', ...
    'Parent', ax);
pdiode_len = 0.05;
hSquare = annotation('rectangle','FaceColor',[1 1 1],'EdgeColor','none', ...
    'Position',[0, 1-pdiode_len, pdiode_len, pdiode_len]); % upper-left

drawnow;

%% Inline key handling (no helper funcs)
keydata.pressed  = '';
keydata.last     = '';
keydata.time_rel = 0;
setappdata(hfig,'keydata',keydata);
tRun = tic; % run clock

set(hfig,'WindowKeyPressFcn', @(~,evt) ...
    setappdata(hfig,'keydata', struct('pressed',evt.Key,'last',evt.Key,'time_rel',toc(tRun))) );

% small utilities inline (no function defs)
get_key = @() getappdata(hfig,'keydata');
clear_key = @() setappdata(hfig,'keydata', struct('pressed','','last',get_key().last,'time_rel',get_key().time_rel));
esc_pressed = @() strcmpi(get_key().last,'escape');

%% Instructions and sync beeps
set(hText,'String', sprintf('INSTRUCTIONS\n\nWhen text appears on the screen,\nread it out loud as accurately as possible.'), ...
    'FontSize', 45, 'Color', 'black');
drawnow;

instrOn = toc(tRun);
log_event(eventFile, 0, instrOn, [], [], [], [], 0, 'Instructions', 0); % flip state unused (0)

disp('Press Spacebar to proceed to experiment');

% wait for space / esc (inline)
keyPressed = '';
while ishghandle(hfig) && ~any(strcmpi(keyPressed, {'space','escape'}))
    kd = get_key();
    keyPressed = kd.pressed;
    pause(0.01);
end
if ~ishghandle(hfig) || strcmpi(keyPressed,'escape')
    log_event(eventFile, 0, toc(tRun), [], [], [], [], TRIG_ESC, 'Escape', 0);
    % graceful shutdown without helper
    try fclose(eventFile); catch, end
    try release(audio_reader); catch, end
    try release(audio_writer); catch, end
    try release(vfd); catch, end
    try close(hfig); catch, end
    return
end
log_event(eventFile, 0, toc(tRun), [], [], [], [], TRIG_KEYPRESS, 'Key Press', 0);
clear_key();

% SYNC beeps
set(hText,'String','SYNC','FontSize',48,'Color','red'); drawnow;
beepWave = 0.1 * sin(2*pi*1000*(0:1/cfg.audio_sample_rate:0.2)); % 200ms
for i = 1:3
    try sound(beepWave, cfg.audio_sample_rate); catch, end
    pause(0.5);
end
set(hText,'String',''); drawnow;

%% Trial Loop main
runStartTime = toc(tRun);
fprintf('Run started (t=%.3fs)\n', runStartTime);

% lag diagnostics (software)
doSoftLag = isfield(cfg,'LAG_DIAGNOSTICS') && cfg.LAG_DIAGNOSTICS && ~cfg.LOCAL_TEST;
lagBuffer = zeros(1, 5000); lagIndex = 1; lagCount = 0;

% breaks
if isfield(cfg,'ntrials') && isfield(cfg,'n_blocks') && cfg.n_blocks > 0
    ntrials_between_breaks = max(1, round(cfg.ntrials / cfg.n_blocks));
else
    ntrials_between_breaks = inf;
end

for itrial = 1:cfg.ntrials
    if ~ishghandle(hfig), break; end

    % scheduled break
    if mod(itrial, ntrials_between_breaks) == 0 && itrial ~= cfg.ntrials
        set(hText,'String','Take a break! Press Spacebar to continue.', 'FontSize', cfg.stim_font_size, 'Color', 'black');
        set(hSquare,'FaceColor',[0.6 0.6 0.6]); drawnow;
        tBreakOn = toc(tRun);
        log_event(eventFile, 0, tBreakOn, [], [], [], [], 0, 'Break message', 0);

        disp('Press Spacebar to continue (3s guard)');
        pause(3);
        keyPressed = '';
        clear_key();
        while ishghandle(hfig) && ~any(strcmpi(keyPressed, {'space','escape'}))
            kd = get_key(); keyPressed = kd.pressed; pause(0.01);
        end
        if ~ishghandle(hfig) || strcmpi(keyPressed,'escape')
            log_event(eventFile, 0, toc(tRun), [], [], [], [], TRIG_ESC, 'Escape', 0);
            break
        end
        log_event(eventFile, 0, toc(tRun), [], [], [], [], TRIG_KEYPRESS, 'Key Press', 0);
        set(hText,'String',''); set(hSquare,'FaceColor',[1 1 1]); drawnow;
        clear_key();
    end

    % trial parameters
    if trials.catch_trial(itrial)
        trialType = 'catch';
        fixColor = [1 0 0];
    else
        trialType = 'speech';
        fixColor = [0 0 0];
    end
    delay_samples = cfg.audio_sample_rate * trials.delay(itrial) / 1000;

    % flush delay pipeline
    try
        for f = 1:maxDelayFrames
            audio_writer(zeros(cfg.audio_frame_size,1));
            vfd(zeros(cfg.audio_frame_size,1), delay_samples);
        end
        reset(vfd);
    catch
    end

    % Start-trial gate (space/esc), except trial 1 if you prefer autostart; here we still gate
    set(hText,'String','Press SPACE to start next trial','FontSize', cfg.stim_font_size, 'Color',[0 0 0]);
    set(hSquare,'FaceColor',[1 1 1]); drawnow;
    keyPressed = '';
    clear_key();
    while ishghandle(hfig) && ~any(strcmpi(keyPressed, {'space','escape'}))
        kd = get_key(); keyPressed = kd.pressed; pause(0.01);
    end
    if ~ishghandle(hfig) || strcmpi(keyPressed,'escape')
        log_event(eventFile, 0, toc(tRun), [], [], [], [], TRIG_ESC, 'Escape', 0);
        break
    end
    log_event(eventFile, 0, toc(tRun), [], [], [], [], TRIG_KEYPRESS + TRIG_ITI, 'Key Press', 0);
    set(hText,'String',''); drawnow;
    clear_key();

    % ITI with fixation cross
    set(hText,'String','*','FontSize', cfg.stim_font_size, 'Color', fixColor);
    set(hSquare,'FaceColor',[0.3 0.3 0.3]); drawnow;
    itiOn = toc(tRun);
    ItiDuration = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);
    log_event(eventFile, 0, itiOn, ItiDuration, [], trialType, [], TRIG_ITI, 'Fixation_Cross_Onset', 0);
    trials.fix_time(itrial) = itiOn;

    % Wait for ITI to finish with ESC check
    tEndITI = itiOn + ItiDuration;
    while ishghandle(hfig) && toc(tRun) < tEndITI
        if esc_pressed()
            log_event(eventFile, 0, toc(tRun), [], [], trialType, [], TRIG_ESC, 'Escape', 0);
            break
        end
        pause(0.005);
    end
    if ~ishghandle(hfig) || esc_pressed(), break; end

    % Visual stimulus ON
    wrapped_text = text_wrapped_all{trials.stim_idx(itrial)};
    set(hText,'String',wrapped_text,'FontSize',cfg.stim_font_size,'Color','black');
    set(hSquare,'FaceColor',[0 0 0]); drawnow;
    stimOnsetTime = toc(tRun);
    trials.visual_onset_time(itrial) = stimOnsetTime;
    log_event(eventFile, 0, stimOnsetTime, [], [], trialType, trials.stim{itrial}, TRIG_VISUAL, 'Visual On', 0);

    % Streaming loop (speech trials only)
    if ~trials.catch_trial(itrial) && ~cfg.LOCAL_TEST
        trialStart = toc(tRun);
        frameCounter = 0;
        while ishghandle(hfig) && (toc(tRun) - trialStart) < cfg.text_stim_dur
            if esc_pressed()
                log_event(eventFile, 0, toc(tRun), [], [], trialType, [], TRIG_ESC, 'Escape', 0);
                break
            end
            tFrame = tic;
            try
                audioIn  = audio_reader();
                delayed  = vfd(audioIn, delay_samples);
                audioOut = max(min(cfg.audio_playback_gain * delayed, 1), -1);
                audio_writer(audioOut);
            catch
                pause(cfg.audio_frame_size / max(1,cfg.audio_sample_rate));
            end

            if doSoftLag
                frameDur_ms = 1000 * (cfg.audio_frame_size / cfg.audio_sample_rate);
                proc_ms     = 1000 * toc(tFrame);
                lag_ms      = max(proc_ms - frameDur_ms, 0);
                lagBuffer(lagIndex) = lag_ms;
                lagIndex = mod(lagIndex, numel(lagBuffer)) + 1;
                lagCount = min(lagCount+1, numel(lagBuffer));
            end

            frameCounter = frameCounter + 1;
            if mod(frameCounter,10) == 0, drawnow; end
        end

        % DAF flush tail
        try
            for f = 1:maxDelayFrames
                audioOut = vfd(zeros(cfg.audio_frame_size,1), delay_samples);
                audio_writer(audioOut);
            end
            reset(vfd);
        catch
        end
        pause(0.1);

        % DAF Off
        log_event(eventFile, 0, toc(tRun), [], [], trialType, [], TRIG_DAF, 'DAF Off', 0);
    else
        % Catch or LOCAL_TEST: just wait the display duration with ESC check
        t0 = toc(tRun);
        while ishghandle(hfig) && (toc(tRun) - t0) < cfg.text_stim_dur
            if esc_pressed()
                log_event(eventFile, 0, toc(tRun), [], [], trialType, [], TRIG_ESC, 'Escape', 0);
                break
            end
            pause(0.005);
        end
    end
    if ~ishghandle(hfig) || esc_pressed(), break; end

    % Visual OFF
    set(hText,'String',''); set(hSquare,'FaceColor',[1 1 1]); drawnow;
    visOffTime = toc(tRun);
    trials.visual_off_time(itrial) = visOffTime;
    log_event(eventFile, 0, visOffTime, [], [], trialType, [], TRIG_VISUAL, 'Visual Off', 0);

    % Status + incremental write
    elapsed = toc(tRun) - runStartTime;
    fprintf('Trial %2i / %i completed at %02d:%02d \n', itrial, cfg.ntrials, floor(elapsed/60), round(mod(elapsed,60)));
    if itrial == 1
        writetable(trials(1,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteVariableNames', true);
    else
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteMode', 'append', 'WriteVariableNames', false);
    end
end

%% Cleanup section (inline, no helper function)
log_event(eventFile, 0, toc(tRun), [], [], [], [], 0, 'End_Message', 0);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n', ...
    cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));
fprintf('RUN ID: %i\n',cfg.RUN_ID);

try release(audio_reader); catch, end
try release(audio_writer); catch, end
try release(vfd); catch, end
try close(hfig); catch, end
try fclose(eventFile); catch, end

end