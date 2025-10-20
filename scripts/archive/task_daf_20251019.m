function task_daf(cfg)

%% in this version we've gotten rid of almost all psychtoolbox functions, but the old PTB code remains commented out 

%%%% run delayed auditory feedback task; in or out of operating room
% by Sam Hansen (SH), Andrew Meier (AM); adapted from other Brain Modulation Lab (BML) scripts

%% Task specific parameters
% Fixation Cross ITI parameters
ITI_S = [1.75, 2.25]; % duration range in seconds of ITI

% Trigger codes for event marking
TRIG_ITI = 1; % Trigger for start of ITI
TRIG_VISUAL = 2; % Visual stimulus onset/offset
TRIG_DAF = 4; % Delayed auditory feedback on/off
TRIG_KEY = 8; % Keyboard escape key press

%% Trial table
[cfg, trials] = create_trials_table(cfg);

%% Initializing log files
eventFile = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n'); %BIDS event file in system time coord

%% Hardware setup
fprintf('Initializing psychtoolbox at %s for subject %s, %s task, session %s, run %i\n\n', ...
    datestr(now,'HH:mm:ss'), cfg.SUBJECT, cfg.TASK, cfg.SESSION_LABEL, cfg.RUN_ID);

% Initialize Keyboard
fprintf('Initializing Keyboard...'); 
if isempty(cfg.KEYBOARD_ID)
    fprintf('\nNo keyboard selected, using default. Choose KEYBOARD_ID from this table:\n'); 
    if ~cfg.LOCAL_TEST
        devices = struct2table(PsychHID('Devices'));
    else
        % Simulate or set dummy device info for local test
        devices = table();
        fprintf('Skipping PsychHID device enumeration for local test mode.\n');
    end
    disp(devices);
end
% % % 
% % % % Initialize Psychtoolbox sound with low latency
% % % InitializePsychSound(1);
% % % 
% % % % Audio device selection and opening for full duplex playback and recording
% % % if ~cfg.LOCAL_TEST
% % %     pa_tbl = struct2table(PsychPortAudio('GetDevices'));    
% % %     % Select output and input devices based on Host API and user configuration
% % %     apiMask = contains(pa_tbl.HostAudioAPIName, cfg.HOST_AUDIO_API_NAME, 'IgnoreCase', true);
% % %     outMask = apiMask & pa_tbl.NrOutputChannels > 0;
% % %     if isfield(cfg,'AUDIO_DEVICE_OUT') && ~isempty(cfg.AUDIO_DEVICE_OUT)
% % %         outMask = outMask & contains(pa_tbl.DeviceName, cfg.AUDIO_DEVICE_OUT, 'IgnoreCase', true);
% % %     end
% % %     if ~any(outMask)
% % %         disp(pa_tbl); error('No OUTPUT device matched HostAPI "%s".', cfg.HOST_AUDIO_API_NAME);
% % %     end
% % %     [~, io] = max(pa_tbl.NrOutputChannels(outMask));
% % %     outIdx = find(outMask);
% % %     outIdx = outIdx(io);
% % %     cfg.AUDIO_ID = pa_tbl.DeviceIndex(outIdx);
% % %     pa_channels = min(2, pa_tbl.NrOutputChannels(outIdx));
% % % 
% % %     % Input selection
% % %     inMask = apiMask & pa_tbl.NrInputChannels > 0;
% % %     if isfield(cfg,'AUDIO_DEVICE_IN') && ~isempty(cfg.AUDIO_DEVICE_IN)
% % %         inMask = inMask & contains(pa_tbl.DeviceName, cfg.AUDIO_DEVICE_IN, 'IgnoreCase', true);
% % %     end
% % %     if ~any(inMask)
% % %         disp(pa_tbl); error('No INPUT device matched HostAPI "%s".', cfg.HOST_AUDIO_API_NAME);
% % %     end
% % %     [~, ii] = max(pa_tbl.NrInputChannels(inMask));
% % %     inIdx = find(inMask);
% % %     inIdx = inIdx(ii);
% % %     cfg.AUDIO_IN_ID = pa_tbl.DeviceIndex(inIdx);
% % % 
% % %     % Open audio devices: master playback, recorder, and slave for output routing
% % %     pa_mode = 1 + 8; % playback + master
% % %     pa_reqlatencyclass = 0; % robust low-latency
% % % 
% % %     % AM added the following line [PsychPortAudio('Close')] to make sure that the master audio device
% % %     % is closed before trying to open it (it might still be open if script
% % %     % was run and aborted before closing)
% % %     PsychPortAudio('Close')
% % %     cfg.pa_master = PsychPortAudio('Open', cfg.AUDIO_ID, pa_mode, pa_reqlatencyclass, [], pa_channels);
% % %     statusMaster = PsychPortAudio('GetStatus', cfg.pa_master);
% % %     Fs = statusMaster.SampleRate;
% % %     fprintf('Using hardware sample rate: %d Hz\n', Fs);
% % % 
% % %     %%%% open recorder & slave with same Fs
% % %     % AM note: some other BML scripts force the audio recording device to
% % %     % have the same sample rate (arugment 5 in PsychPortAudio('Open')) as master device; 
% % %     % however this causes errors when master = Radial USB and recording = Focusrite
% % %     cfg.pa_rec = PsychPortAudio('Open', cfg.AUDIO_IN_ID, 2, pa_reqlatencyclass, [], 1);
% % %     cfg.pa_slave3 = PsychPortAudio('OpenSlave', cfg.pa_master, 1, pa_channels);
% % % 
% % %     % Prime device buffers and start audio streams
% % %     PsychPortAudio('GetAudioData', cfg.pa_rec, 10);
% % %     PsychPortAudio('Start', cfg.pa_master, 0, 0, 0);
% % %     WaitSecs(0.02);
% % %     PsychPortAudio('Start', cfg.pa_rec, 0, 0, 0);
% % % else
% % %     % Local test mode: skip hardware setup and use default parameters
% % %     fprintf('LOCAL_TEST: skipping audio setup\n');
% % %     Fs = 48000;
% % %     cfg.pa_master = [];
% % %     cfg.pa_rec = [];
% % %     cfg.pa_slave3 = [];
% % % end
% % % 
% % % % Compute delay times in audio samples from milliseconds, store in map
% % % uniqueDelaysMs = unique(round(cfg.delayOptions(:)));
% % % delayMsToSamples = containers.Map('KeyType','int32','ValueType','double');
% % % for k = 1:numel(uniqueDelaysMs)
% % %     delayMsToSamples(int32(uniqueDelaysMs(k))) = Fs * (uniqueDelaysMs(k)/1000);
% % % end
% % % 
% % % % Map trial delay ms to samples (double precision for accuracy)
% % % ntrials = height(trials);
% % % trialDelaySamples = zeros(ntrials,1,'double');
% % % for i = 1:ntrials
% % %     trialDelaySamples(i) = delayMsToSamples(int32(round(trials.delay(i))));
% % % end
% % % 
% % % % Configure max delay for fractional delay filter and create filter instance
% % % maxDelaySamples = max(ceil(max(trialDelaySamples)), round(0.25 * Fs) );
% % % vfd = dsp.VariableFractionalDelay('MaximumDelay', maxDelaySamples);
% % % 
% % % % Default background color if not specified, normalized just before window open
% % % if ~isfield(cfg,'bg_color')
% % %     cfg.bg_color = [255 255 255];
% % % end
% % % 
% % % % Normalize color
% % % if max(cfg.bg_color) > 1
% % %     cfg.bg_color = double(cfg.bg_color)./255;
% % % end
% % % 
% % % % Get the largest screen number (usually the main display)
% % % scr = max(Screen('Screens'));
% % % 
% % % % Open Psychtoolbox screen window, fullscreen or windowed depending on mode
% % % if cfg.LOCAL_TEST
% % %     % Tell PTB to create a real GUI window instead of fullscreen
% % %     PsychImaging('PrepareConfiguration');
% % %     PsychImaging('AddTask', 'General', 'UseGUIWindow');
% % %     debugWindowWidth = 1024;
% % %     debugWindowHeight = 640;
% % %     sr = Screen('Rect', scr);
% % %     cx = (sr(3)-debugWindowWidth)/2;
% % %     cy = (sr(4)-debugWindowHeight)/2;
% % %     windowRect = [cx, cy, cx+debugWindowWidth, cy+debugWindowHeight];
% % %     [window, ~] = PsychImaging('OpenWindow', scr, cfg.bg_color, windowRect);
% % %     fprintf('Opened PTB LOCAL_TEST in a real desktop window (%dx%d, resizable/movable)\n', ...
% % %             debugWindowWidth, debugWindowHeight);
% % % else
% % %     % Standard fullscreen mode
% % %     [window, ~] = PsychImaging('OpenWindow', scr, cfg.bg_color);
% % % end
% % % 
% % % % Set alpha blending for smooth text and stimuli
% % % Screen('BlendFunction', window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
% % % Screen('TextSize', window, cfg.stim_font_size);
% % % 
% % % % Build an offscreen texture for each wrapped stim text
% % % stimTex = nan(cfg.n_unique_stim,1);
% % % textColor = [0 0 0];
% % % for si = 1:cfg.n_unique_stim
% % %     off = Screen('OpenOffscreenWindow', window, cfg.bg_color);
% % %     Screen('TextSize', off, cfg.stim_font_size); 
% % % % % % % % %     DrawFormattedText(off, text_wrapped_all{si}, 'center', 'center', textColor); % commented out and replaced by AM 2025/10/18
% % %     DrawFormattedText(off, trials.stim{si}, 'center', 'center', textColor); 
% % %     stimTex(si) = off;
% % % end
% % % 
% % % % Calculate fixation cross coordinates and properties for drawing
% % % [winW, winH] = Screen('WindowSize', window);
% % % [cx, cy] = RectCenter([0 0 winW winH]);
% % % arm = 40;
% % % lw = 5;
% % % xy = [ cx-arm, cx+arm, cx, cx;
% % %     cy, cy, cy-arm, cy+arm ];

% Set up keyboard escape key identification and priority
KbName('UnifyKeyNames');
ESC = KbName('ESCAPE');
device = []; % default keyboard
% % % 
% % % if ~cfg.LOCAL_TEST
% % %     Priority(MaxPriority(window)); % raise MATLAB priority for experiment timing
% % % else
% % %     Priority(0); % normal priority for debug mode
% % % end

% Enable keyboard listening without echoing characters to command window
ListenChar(0);
ShowCursor;
% % % 
% % % %% ******************************************************************** %%
% % % %                         TASK SPECIFIC SECTION                          %
% % % %  ********************************************************************  %
% % % 
% % % fprintf('%s Task run is starting...\n', cfg.TASK);
% % % fprintf('\nStarting run %i at %s \n',cfg.RUN_ID,datestr(now,'HH:MM:SS am'));
% % % fprintf('RUN ID: %i\n\n',cfg.RUN_ID);
% % % 
% % % %% Display instructions screen and wait for keypress to start
% % % instr = 'INSTRUCTIONS\n\nWhen text appears on the screen,\n Read as quickly and accurately as possible.\n\nPress any key to begin...';
% % % Screen('FillRect', window, cfg.bg_color);
% % % DrawFormattedText(window, instr, 'center', 'center', [0 0 0]);
% % % [instrOn, ~] = Screen('Flip', window);
% % % KbReleaseWait(device); % swallow any prior keypress
% % % [~, keyCode] = KbStrokeWait(device); % blocks until a key is pressed
% % % 
% % % goto_cleanup = keyCode(ESC) > 0; % exit if ESC pressed here
% % % if goto_cleanup
% % %     if ~cfg.LOCAL_TEST
% % %         try PsychPortAudio('Stop',  cfg.pa_slave3, 1, 1); catch, end
% % %         try PsychPortAudio('Stop',  cfg.pa_rec,    1, 1); catch, end
% % %         try PsychPortAudio('Stop',  cfg.pa_master, 1, 1); catch, end
% % %         try PsychPortAudio('Close', cfg.pa_slave3);       catch, end
% % %         try PsychPortAudio('Close', cfg.pa_rec);          catch, end
% % %         try PsychPortAudio('Close', cfg.pa_master);       catch, end
% % %     end
% % %     try Screen('CloseAll'); catch, end
% % %     try fclose(eventFile);  catch, end
% % %     try KbQueueRelease;     catch, end
% % %     try Priority(0);        catch, end
% % %     try ListenChar(0);      catch, end
% % %     try ShowCursor;         catch, end
% % %     return
% % % end



%% Audio setup

% List available audio input devices.... sometimes crashes matlab on intraop rig Alienware laptop 
input_devices = getAudioDevices(audioDeviceReader); 
for k = 1:length(input_devices)
    fprintf('%d: %s\n', k, input_devices{k});
end
inIdx = input('INPUT device #: '); % User selects input device

% if using focusrite on BML intraop rig, specify the correct audio driver
if ispc % If running on a Windows
    [~,host] = system('hostname');
    host     = deblank(host);
elseif ismac % If running on a Mac
    [~,host] = system('scutil --get LocalHostName');
    host     = deblank(host);
end
if strcmp(host,'BML-ALIENWARE2')
    reader = audioDeviceReader('SampleRate', cfg.audio_sample_rate, ...
        'SamplesPerFrame', cfg.audio_frame_size, ...
        'Device', 'Focusrite USB ASIO',...
        'Driver','ASIO'); % Live mic input  
else
    reader = audioDeviceReader('SampleRate', cfg.audio_sample_rate,...
        'SamplesPerFrame', cfg.audio_frame_size,...
        'Device', input_devices{inIdx}); % Live mic input
end

output_devices = getAudioDevices(audioDeviceWriter); % List available audio output devices
for k = 1:length(output_devices)
    fprintf('%d: %s\n', k, output_devices{k});
end
outIdx = input('OUTPUT device #: '); % User selects output device

writer = audioDeviceWriter('SampleRate', cfg.audio_sample_rate, 'Device', output_devices{outIdx}); % Speaker output
vfd = dsp.VariableFractionalDelay('MaximumDelay', round(cfg.audio_sample_rate)); % Delay buffer for DAF
for k = 1:10, writer(reader()); end % Prime audio pipeline (avoid startup glitch)
maxDelay_ms = max(cfg.delay_values_ms); % Find largest delay (ms)
maxDelayFrames = ceil((maxDelay_ms/1000) * cfg.audio_sample_rate / cfg.audio_frame_size) + 5; % Max delay in frames, add buffer

%% Stimulus figure setup
screenSize = get(0, 'ScreenSize'); % Get screen size for centering
fig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none','Position',[screenSize(3)/4 screenSize(4)/4 900 600],'NumberTitle','off'); % Main experiment window
ax = axes('Parent',fig,'Position',[0 0 1 1],'Visible','off'); % Invisible axes for center-center text
hText = text(0.5, 0.5, '', ...
    'FontSize', cfg.stim_font_size, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Units','normalized', ...
    'Parent', ax); % Centered text object for all instructions/cues
stopFig = figure('Name','Stop','NumberTitle','off','MenuBar','none','ToolBar','none','Position',[300 100 200 80]); % Stop window
setappdata(0, 'stopReq', false); % Shared flag for stopping experiment
uicontrol(stopFig,'Style','pushbutton','String','Stop','FontSize',14,'Position',[50 20 100 40],'Callback', @(~,~) setappdata(0,'stopReq',true)); % Stop button sets flag

%% Instructions and sync beeps
instructions = [
    'INSTRUCTIONS\n\n' ...
    'When text appears on the screen,\n'...
    'Read as quickly and accurately as possible.\n\n' ...
    'Press any key to begin...'
];
set(hText, 'String', sprintf(instructions), ...
    'FontSize', 55, ...
    'Color', 'black'); % Show instructions
figure(fig); % Bring main window to front
instrOn = GetSecs(); % get instructions presentation time
set(fig, 'WindowKeyPressFcn', @(~,~) uiresume(fig)); % Resume on any key
uiwait(fig); % Wait for user keypress
set(fig, 'WindowKeyPressFcn', ''); % Remove keypress handler
set(hText, 'String', ''); drawnow; % Clear text
beepWave = 0.1 * sin(2*pi*1000*(0:1/cfg.audio_sample_rate:0.2)); % 200ms, 1kHz beep
set(hText, 'String', 'SYNC', 'FontSize', 48, 'Color', 'red'); drawnow; % Show sync message
syncTime = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'); % Log sync time (for aligning with other systems)
for i = 1:3
    if i == 1
        refTime = GetSecs; % Start experiment timer at first beep
    end
    sound(beepWave, cfg.audio_sample_rate);
    pause(0.5);
end
set(hText, 'String', ''); drawnow; % Clear after last beep

% Initialize keyboard queue for low-latency key detection during task
KbQueueCreate(device);
KbQueueStart(device); 

% Initialize clocks for event timing
baseGetSecs = GetSecs();
baseClock = datetime('now','TimeZone','local');

% Log instruction onset using flip timestamp
flipSyncState = 0;
flipSyncState = ~flipSyncState;
log_event(eventFile, 0, instrOn, [], [], [], [], 0, 'Instructions', flipSyncState);


%% Trial Loop main
runStartTime = GetSecs();
speechVsCatch = '';
blockFrames = 4;
frameSamples = cfg.audio_frame_size;
blockSamples = blockFrames * frameSamples;
streamBufStereo = zeros(2, blockSamples, 'double');
goto_cleanup = false;

% Check if lag diagnostics enabled
doSoftLag = isfield(cfg,'LAG_DIAGNOSTICS') && cfg.LAG_DIAGNOSTICS && ~cfg.LOCAL_TEST;
lagBuffer = zeros(1, 5000); lagIndex = 1; lagCount = 0; completedTrials = 0; % Buffers for audio latency diagnostics

for itrial = 1:cfg.ntrials
    % Check for user abort with ESC key
    [isDown, ~, kc] = KbQueueCheck(device);
    if isDown && kc(ESC)
        flipSyncState = ~flipSyncState;
        code = TRIG_KEY;
        log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], speechVsCatch, [], code, 'Escape/Stop', flipSyncState);
        goto_cleanup = true; break;
    end

    % Set params depending on whether trial is catch (no speech) or speech trial
    if trials.catch_trial(itrial)
        speechVsCatch = 'catch';
        fixColor = [255 0 0];
    else
        speechVsCatch = 'speech';
        fixColor = [0 0 0];
    end

% % %     delay_samples = trialDelaySamples(itrial);

    delay_samples = cfg.audio_sample_rate * trials.delay(itrial) / 1000; % Trial parameters 
        
    for iframe = 1:maxDelayFrames
        writer(zeros(cfg.audio_frame_size,1)); % Flush output buffer
        vfd(zeros(cfg.audio_frame_size,1), delay_samples); % Flush delay buffer
    end
    vfd.reset(); % Reset delay state

    % Display diagnostic info about trial start
    fprintf('Starting trial %d with stim index %d and delay %d ms\n', itrial, trials.stim_idx(itrial), trials.delay(itrial));

    % ITI with fixation cross display and log
% % %     Screen('FillRect', window, cfg.bg_color);
% % %     Screen('DrawLines', window, xy, lw, fixColor);

    set(hText, 'String', '*', 'FontSize', cfg.stim_font_size, 'Color', ifelse(~trials.catch_trial(itrial), [0.7 0.7 0.7], 'red')); % Show asterisk cue
    drawnow;
    itiFixOnTime = GetSecs; 


    flipSyncState = ~flipSyncState;

% % %    [itiFixOnTime, ~] = Screen('Flip', window);

    % record the time when fixation cross comes on
    trials.fix_time(itrial) = baseClock + seconds(itiFixOnTime - baseGetSecs);
    
    ItiDuration = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);
    code = TRIG_ITI;
    log_event(eventFile, cfg.DIGOUT, itiFixOnTime, ItiDuration, [], speechVsCatch, [], code, 'Fixation_Cross_Onset', flipSyncState);
    
    % ITI wait loop with abort check loop
    tEnd = itiFixOnTime + ItiDuration;
    while GetSecs < tEnd
        [isDown, ~, kc] = KbQueueCheck(device);
        if isDown && kc(ESC)
            flipSyncState = ~flipSyncState;
            log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], speechVsCatch, [], TRIG_ITI + TRIG_KEY, 'Escape/Stop', flipSyncState);
            goto_cleanup = true;
            break
        end
    end
    WaitSecs(0.005);
    if goto_cleanup, break; end

% % %     % Pre stim blank screen followed by configured delay before stimulus
% % %     Screen('FillRect', window, cfg.bg_color);
% % %     Screen('Flip', window);


    WaitSecs(cfg.delay_dur);

    % DAF audio playback start (for speech trials, non-local mode only)
% % %     if isSpeak && ~cfg.LOCAL_TEST
% % %         % Prefill silence to give the slave FIFO some headroom:
% % %         prefill = zeros(pa_channels, round(0.25 * Fs), 'double');
% % %         PsychPortAudio('FillBuffer', cfg.pa_slave3, prefill);
% % %         reset(vfd);
% % %         PsychPortAudio('Start', cfg.pa_slave3, 0, 0, 0);
% % %         flipSyncState = ~flipSyncState;
% % %         code = TRIG_DAF;
% % %         dafTriggerTime = GetSecs();
% % %         log_event(eventFile, cfg.DIGOUT, dafTriggerTime, [], [], trialType, [], code, 'DAF On', flipSyncState);
% % %     end

    % Visual stimulus on: draw text texture and flip screen
    set(hText, 'String', trials.stim{itrial}, 'FontSize', cfg.stim_font_size, 'Color', 'black'); drawnow; % Show sentence
    stimOnsetTime = GetSecs(); 

% % %     Screen('FillRect', window, cfg.bg_color);
% % %     Screen('DrawTexture', window, stimTex(trials.stim_idx(itrial)));
    flipSyncState = ~flipSyncState;
% % %     [stimOnsetTime, ~] = Screen('Flip', window);
    trials.visual_onset_time(itrial) = baseClock + seconds(stimOnsetTime - baseGetSecs);
    code = TRIG_VISUAL;
    text_stim = trials.stim{itrial};
    log_event(eventFile, cfg.DIGOUT, stimOnsetTime, [], [], speechVsCatch, text_stim, code, 'Visual Onset', flipSyncState);

    % Streaming Loop: read microphone audio, apply delay, output delayed audio
    if ~trials.catch_trial(itrial) && ~cfg.LOCAL_TEST
% % %         KbQueueFlush(device);
% % %         trialStart = GetSecs();
% % %         if doSoftLag
% % %             lagSum = 0; 
% % %             lagN   = 0;
% % %         end
% % %         while (GetSecs - trialStart) < cfg.text_stim_dur
% % %             % ESC abort check in streaming loop
% % %             [pressed, fp] = KbQueueCheck(device);
% % %             if pressed && fp(ESC) > 0
% % %                 flipSyncState = ~flipSyncState;
% % %                 log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], speechVsCatch, [], TRIG_KEY, 'Escape/Stop', flipSyncState);
% % %                 goto_cleanup = true;
% % %                 break
% % %             end
% % %     
% % %             % Non-blocking audio input read with max length blockSamples
% % %             [a, tCapFirst, ~] = PsychPortAudio('GetAudioData', cfg.pa_rec, [], 0, 0, 1);
% % % 
% % %             % Mix stereo to mono if needed, zero pad or truncate
% % %             if ~isempty(a)
% % %                 if size(a,1) > 1, a = mean(a,1); end % mixdown to mono
% % %                 a = a(:);
% % %             else
% % %                 a = single([]); % keep type stable
% % %             end
% % %             n = numel(a);
% % %             if n < blockSamples
% % %                 a = [a; zeros(blockSamples-n,1,'single')];
% % %             elseif n > blockSamples
% % %                 a = a(end-blockSamples+1:end);
% % %             end
% % % 
% % %             % Apply configured fractional delay to input audio block
% % %             delayed = vfd(single(a), single(delay_samples));
% % %             y = double(delayed(:)).' * cfg.audio_playback_gain;
% % %             y = max(min(y, 1), -1);
% % %             
% % %             % Optional soft lag diagnostics tracking delay performance
% % %             if doSoftLag && ~isempty(tCapFirst) && n > 0
% % %                 tCapLast = tCapFirst + (min(n, blockSamples)-1)/Fs; % timestamp for last captured sample in this block
% % %                 tEnq = GetSecs();
% % %                 extra_s = (tEnq - tCapLast) - double(delay_samples)/Fs; % extra over requested delay
% % %                 if extra_s > 0
% % %                     lagSum = lagSum + extra_s;
% % %                     lagN = lagN + 1;
% % %                 end
% % %             end
% % % 
% % %             % Fill output buffers for either stereo or mono output
% % %             if pa_channels >= 2
% % %                 streamBufStereo(1,:) = y;
% % %                 streamBufStereo(2,:) = y;
% % %                 PsychPortAudio('FillBuffer', cfg.pa_slave3, streamBufStereo, 1); % streaming refill
% % %             else
% % %                 PsychPortAudio('FillBuffer', cfg.pa_slave3, y, 1);
% % %             end
% % %         end
% % % 
% % %         % Save mean lag time in milliseconds for trial, or NaN if none measured
% % %         if doSoftLag && lagN > 0
% % %             trials.lag_mean(itrial) = 1000 * (lagSum / lagN);
% % %         else
% % %             trials.lag_mean(itrial) = NaN;
% % %         end
% % % 
% % %         if goto_cleanup, break; end

        DAop.audio_sample_ratetart = GetSecs;
        frameCounter = 0;
        while (GetSecs - DAop.audio_sample_ratetart) < cfg.text_stim_dur && ~getappdata(0,'stopReq') % While within trial duration and not stopped
            tStart = GetSecs; % Start timing for this frame
            audioIn = reader(); 
            delayed = vfd(audioIn, delay_samples); % Get input, apply delay
            audioOut = max(min(cfg.audio_playback_gain * delayed, 1), -1); % Apply gain, clip to [-1,1]
            writer(audioOut); % Output delayed audio
            lag = max((GetSecs - tStart)*1000 - (cfg.audio_frame_size/cfg.audio_sample_rate*1000), 0); % Compute audio processing lag in ms
            lagBuffer(lagIndex) = lag; % Store lag
            lagIndex = mod(lagIndex, 5000) + 1; % Circular buffer
            lagCount = min(lagCount+1, 5000);
            frameCounter = frameCounter + 1;
            if mod(frameCounter, 10) == 0
                drawnow; % Update GUI every 10 frames
            end
            pause(0.001); % Prevent CPU slowing
        end
        for iframe = 1:maxDelayFrames
            audioOut = vfd(zeros(cfg.audio_frame_size,1), delay_samples); % Flush remaining delayed audio
            writer(audioOut);
        end
        vfd.reset();
        WaitSecs(0.1); % Short pause to finish playback

    else
        % For catch or local test mode, simple pause loop with key abort check
        t0 = GetSecs();
        while (GetSecs - t0) < cfg.text_stim_dur
            [isDown, ~, kc] = KbQueueCheck(device);
            if isDown && kc(ESC)
                flipSyncState = ~flipSyncState;
                log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], speechVsCatch, [], TRIG_KEY, 'Escape/Stop', flipSyncState);
                goto_cleanup = true;
                break
            end
            WaitSecs(0.005);
        end
    end

    % DAF off
    if ~trials.catch_trial(itrial) && ~cfg.LOCAL_TEST
% % %         PsychPortAudio('Stop', cfg.pa_slave3, 0, 0);
        flipSyncState = ~flipSyncState;
        dafOffTime = GetSecs();
        code = TRIG_DAF;
        log_event(eventFile, cfg.DIGOUT, dafOffTime, [], [], speechVsCatch, [], code, 'DAF Off', flipSyncState);
    end

    % Visual off
% % %     Screen('FillRect', window, cfg.bg_color);

    
    flipSyncState = ~flipSyncState;

    set(hText, 'String', '');
    drawnow; % Clear

% % %     [visOffTime, ~] = Screen('Flip', window);

    visOffTime = GetSecs(); 

    trials.visual_off_time(itrial) = baseClock + seconds(visOffTime - baseGetSecs);
    code = TRIG_VISUAL;
    log_event(eventFile, cfg.DIGOUT, visOffTime, [], [], speechVsCatch, [], code, 'Visual Off', flipSyncState);

    % Display trial completion summary
    elapsed = GetSecs() - runStartTime;
    fprintf('Trial %2i / %i completed at %02d:%02d \n', itrial, cfg.ntrials, floor(elapsed/60), round(mod(elapsed,60)));

    % Save current trial data to disk; write headers only on first occasion
    if itrial == 1
        writetable(trials(1,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteVariableNames', true);
    else
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteMode', 'append', 'WriteVariableNames', false);
    end
end

%% Cleanup section: log final event and safely close resources
flipSyncState = ~flipSyncState;
log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], [], [], 0, 'End Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n', ...
    cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));
fprintf('RUN ID: %i\n',cfg.RUN_ID);

% Release hardware, close windows
release(reader); 
release(writer);
release(vfd);
close(fig);

% % % % Stop and close audio devices
% % % if ~cfg.LOCAL_TEST
% % %     try PsychPortAudio('Stop',  cfg.pa_rec,    1, 1); catch, end
% % %     try PsychPortAudio('Stop',  cfg.pa_master, 1, 1); catch, end
% % %     try PsychPortAudio('Stop',  cfg.pa_slave3, 1, 1); catch, end
% % %     try PsychPortAudio('Close', cfg.pa_slave3);       catch, end
% % %     try PsychPortAudio('Close', cfg.pa_rec);          catch, end
% % %     try PsychPortAudio('Close', cfg.pa_master);       catch, end
% % % end

% % % % Close offscreen text windows
% % % for si = 1:numel(stimTex)
% % %     if ~isnan(stimTex(si)), Screen('Close', stimTex(si)); end
% % % end

% Release keyboard queue, reset priority and listeners, close screen
try KbQueueRelease(device); catch, end
try ListenChar(0);          catch, end
try ShowCursor;             catch, end
try Priority(0);            catch, end
% % % try Screen('CloseAll');     catch, end

% Close the event file safely
try fclose(eventFile);      catch, end

end

%% Helper function (Ternary operator: returns a if cond is true, else b)
function out = ifelse(cond, a, b)
    if cond, out = a;
    else, out = b;
    end
end