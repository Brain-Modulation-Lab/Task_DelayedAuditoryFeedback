function Task_DelayedAuditoryFeedback(cfg)
%% Task specific parameters
    
% Fixation Cross ITI parameters



ITI_S = [1, 1]; % duration range in secconds of ITI
SPACER_VISUAL_AUDIO_S = [0,0]; %duration range for visual sentence onset to audio sentence onset
SPACER_AUDIO_GO_S = [0.25, 0.75]; %duration range for end of audio to GO signal. 
SPACER_AUDIO_GO_TO_DETECTION_ONSET = 0.15; %buffer between end of GO signal and begginging of detection
SPACER_AUDIO_GO_TO_STIMULATION = SPACER_AUDIO_GO_TO_DETECTION_ONSET; %buffer between end of GO signal and begginging of detection

KEYPRESS_S = 0.1; %duration of key press event 
volumeMax = 1;


%% trigger codes
TRIG_ITI = 1; %%%% send this when stim is removed at end of trial
TRIG_VISUAL = 2;
TRIG_TRIAL = 4; %%% send this before fix cross at beginning of trial
TRIG_DAF = 8;
TRIG_KEY = 16; %%% send this 

%% Load sentences and block randomization (with preallocation)
T = readtable([dirs.projrepo, filesep, 'stimuli', filesep, 'daf_sentences.tsv'],...
     'FileType','text', 'Delimiter','\t', 'ReadVariableNames',false);
sentences = T.Var1; % Extract sentences as cell array
nSentences = numel(sentences); % Number of sentences

% For one block: all (sentence x delay) pairs
[sentenceIdxGrid, delayIdxGrid] = ndgrid(1:nSentences, 1:numel(delayOptions));
blockSentIdx = sentenceIdxGrid(:); % [nSentences*numel(delayOptions) x 1]
blockDelays = delayOptions(delayIdxGrid(:)); % [nSentences*numel(delayOptions) x 1]
blockNtrials = numel(blockSentIdx); % Number of trials per block
nTrials = op.n_blocks * blockNtrials; % Total number of trials

trials = table([1:nTrials]',cell(nTrials,1),'VariableNames',{'trialnum','sentence'});

% Preallocate arrays for all trials
trialSentIdx = zeros(nTrials, 1); % Sentence indices for all trials
trialDelays = zeros(nTrials, 1); % Delay values for all trials
trialBlock = zeros(nTrials, 1); % Block number for all trials
trialCounter = 1; % Index for filling arrays
for b = 1:op.n_blocks
    blockOrder = randperm(blockNtrials); % Unique shuffle for this block
    trialRange = trialCounter:(trialCounter + blockNtrials - 1);
    trialSentIdx(trialRange) = blockSentIdx(blockOrder);
    trialDelays(trialRange)  = blockDelays(blockOrder);
    trialBlock(trialRange)   = b;
    trialCounter = trialCounter + blockNtrials;
end

% Assign catch trials randomly across all trials
nCatch = round(nTrials * catchRatio);
isCatch = false(nTrials, 1);
if nCatch > 0
    isCatch(randperm(nTrials, nCatch)) = true;
end

%% warnings and cleanup functions
onCleanupTasks = cell(20,1); %cerating cleanup cell array container to enforce cleanup order

%% Initializing log files

%opening events file
eventFile = fopen(cfg.EVENT_FILENAME, 'a');  % Appending mode
onCleanupTasks{19} = onCleanup(@() fclose(eventFile));
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n'); %BIDS event file in system time coord

%% Initializing psychtoolbox
fprintf('Initializing psychtoolbox at %s for subject %s, %s task, session %s, run %i\n\n',datestr(now,'HH:MM:SS'),cfg.SUBJECT,cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID);

% Initializing Keyboard
fprintf('Initializing Keyboard...'); 
if isempty(cfg.KEYBOARD_ID)
    fprintf('\nNo keyboard selected, using default. Choose KEYBOARD_ID from this table:\n'); 
    % Detect keyboards attached to system
    devices = struct2table(PsychHID('Devices'));  
    disp(devices);
end

KbName('UnifyKeyNames')
keyCodeEscape = KbName('ESCAPE');
fprintf('done\n'); 

% getting audio device id
pa_devices = struct2table(PsychPortAudio('GetDevices'));
pa_devices_sel = contains(pa_devices.HostAudioAPIName,cfg.HOST_AUDIO_API_NAME) & contains(pa_devices.DeviceName,cfg.AUDIO_DEVICE); 
if sum(pa_devices_sel) == 0 
    disp(pa_devices);
    error('%s - %s not found. Choose one from the list of available audio devices',cfg.HOST_AUDIO_API_NAME,cfg.AUDIO_DEVICE);
elseif sum(pa_devices_sel) > 1
    disp(pa_devices);
    error('%s - %s matches more than one device. Choose one from the list of available audio devices',cfg.HOST_AUDIO_API_NAME,cfg.AUDIO_DEVICE);
else
    fprintf('The following audio device was selected');
    disp(pa_devices(pa_devices_sel,:));
    cfg.AUDIO_ID = pa_devices.DeviceIndex(pa_devices_sel);
end
pa_mode = 1+8; %1 == sound playback only; 8 == openning as 'master' device
pa_reqlatencyclass = 1; % Try to get the lowest latency that is possible under the constraint of reliable playback.  
pa_freq = []; %loading default freq for device
pa_channels = 2; %playing as stereo, converting to mono by hardware connector
pa_master = PsychPortAudio('Open', cfg.AUDIO_ID, pa_mode, pa_reqlatencyclass, pa_freq, pa_channels);

% loading audio and verifying output frequency and resampling
pa_handle_status = PsychPortAudio('GetStatus', pa_master);
pa_handle_Fs = pa_handle_status.SampleRate;
onCleanupTasks{18} = onCleanup(@() PsychPortAudio('Close', pa_master));

% starting master device
pa_repetitions = 0;
pa_when = 0;
pa_waitForStart = 0;
PsychPortAudio('Start', pa_master, pa_repetitions, pa_when, pa_waitForStart);
onCleanupTasks{17} = onCleanup(@() PsychPortAudio('Stop', pa_master));

flipSyncState=0;

%% ******************************************************************** %%
%                         TASK SPECIFIC SECTION                          %
%  ********************************************************************  %
%% 
fprintf('%s Task run is starting...\n', cfg.TASK);

% verifying output frequency and resampling
pa_master_status = PsychPortAudio('GetStatus', pa_master);
pa_master_Fs = pa_master_status.SampleRate;


% creating slave audio channel for sentences
pa_slave3 = PsychPortAudio('OpenSlave', pa_master, pa_mode, pa_channels);
onCleanupTasks{7} = onCleanup(@() PsychPortAudio('Close', pa_slave3));
onCleanupTasks{6} = onCleanup(@() fprintf('Cleaning up.\n'));

fprintf('\nPress any key to advance trial. \nPress ESCAPE to end run.\n');
fprintf('\nStarting run %i at %s \n',cfg.RUN_ID,datestr(now,'HH:MM:SS am'));
fprintf('RUN ID: %i\n\n',cfg.RUN_ID);
% commandwindow;
% WaitSecs(0.1);

%% GUI setup
screenSize = get(0, 'ScreenSize'); % Get screen size for centering
fig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none','Position',[screenSize(3)/4 screenSize(4)/4 900 600],'NumberTitle','off'); % Main experiment window
ax = axes('Parent',fig,'Position',[0 0 1 1],'Visible','off'); % Invisible axes for center-center text
hText = text(0.5, 0.5, '', ...
    'FontSize', op.stim_font_size, ...
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
set(fig, 'WindowKeyPressFcn', @(~,~) uiresume(fig)); % Resume on any key
uiwait(fig); % Wait for user keypress
set(fig, 'WindowKeyPressFcn', ''); % Remove keypress handler
set(hText, 'String', ''); drawnow; % Clear text

flipSyncState = ~flipSyncState;
welcomeMesageTime = GetSecs();
log_event(eventFile, cfg.DIGOUT, welcomeMesageTime, [], [], [], [], 0, 'Instructions', flipSyncState);

%%
% waiting for next trial keypress
[keyPressTime, keyCode] = KbWait(cfg.KEYBOARD_ID, 2);
log_event(eventFile, cfg.DIGOUT, keyPressTime, [], [], [], [], TRIG_KEY, 'Key Pressed', flipSyncState);
startRunTime = keyPressTime;

if any(ismember(find(keyCode),keyCodeEscape))
    code = TRIG_KEY;
    log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], code, 'Escape', flipSyncState);
    fprintf("Escape key detected, ending run.\n");
    return
end

% setting ITI fixation cross
flipSyncState = ~flipSyncState;
ItiOnsetTime = GetSecs();
ItiDuration = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);    
log_event(eventFile, cfg.DIGOUT, ItiOnsetTime, ItiDuration, [], [], [], TRIG_ITI, 'ITI', flipSyncState);

%% Trial Loop
nTrials = height(DAF_Trials);

% Initialize lag diagnostics
lagBuffer = zeros(1, 5000);
lagIndex = 1;
lagCount = 0;

    for idxTrial = 1:nTrials
        trialType = DAF_Trials.stim_epoch{idxTrial};

        % Check for exit keypress
        if any(ismember(find(keyCode), keyCodeEscape))
            code = TRIG_ITI + TRIG_KEY;
            log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], code, 'Escape', flipSyncState);
            fprintf("Escape key detected, ending run.\n");
            break
        end

        % Trial parameters and stimulus preparation
        sIdx = trialSentIdx(idxTrial);
        delay_ms = trialDelays(idxTrial);
        delay_samples = round(op.audio_sample_rate * delay_ms / 1000);
        text_stim = sentences{sIdx};
        isSpeak = ~isCatch(idxTrial);
        text_stim_wrapped = textwrap({text_stim}, op.stim_max_char_per_line);

        % Flush slave playback audio buffers before trial start
        PsychPortAudio('FillBuffer', pa_slave3, zeros(pa_channels, op.audio_frame_size * maxDelayFrames));
        vfd.reset();

        % Present visual fixation cross and log visual trigger
        visTriggerTime = GetSecs();
        code = TRIG_TRIAL;
        log_event(eventFile, cfg.DIGOUT, visTriggerTime, [], [], trialType, [], code, 'Trial Onset', flipSyncState);
        Screen('FillRect', window, op.bg_color);
        DrawFormattedText(window, '*', 'center', 'center', ifelse(isSpeak,[180 180 180],[255 0 0]));
        Screen('Flip', window);
        WaitSecs(op.fix_cross_dur);

        % Pre-sentence blank screen
        Screen('FillRect', window, op.bg_color);
        Screen('Flip', window);
        WaitSecs(op.delay_dur);

        % Show sentence text and record onset
        flipSyncState = ~flipSyncState;
        code = TRIG_VISUAL;
	    log_event(eventFile, cfg.DIGOUT, SentenceOnsetTime, [], [], trialType, dbTrials.file_text{idxTrial}, code, 'Visual Onset', flipSyncState);
        Screen('FillRect', window, op.bg_color);
        DrawFormattedText(window, text_stim_wrapped{:}, 'center', 'center', [0 0 0]);
        [~, stimOnsetTime] = Screen('Flip', window);

        % Clear sentence and log visual off trigger
        Screen('FillRect', window, op.bg_color);
        [visOffTime, ~] = Screen('Flip', window);
        code = TRIG_VISUAL;
        log_event(eventFile, cfg.DIGOUT, visOffTime, [], [], trialType, [], code, 'Visual Off', flipSyncState);

        % Start DAF playback on slave device, log trigger
        dafTriggerTime = GetSecs();
        code = TRIG_DAF;
        log_event(eventFile, cfg.DIGOUT, dafTriggerTime, [], [], trialType, [], code, 'DAF Trigger', flipSyncState);
        PsychPortAudio('Start', pa_slave3, 0, 0, 1);

        % Audio streaming loop for delayed auditory feedback
        if isSpeak && delay_ms > 0
            frameCounter = 0;
            trialStart = dafTriggerTime;
            while (GetSecs - trialStart) < op.text_stim_dur && ~getappdata(0,'stopReq')
                tStart = GetSecs;

                % Read audio input from master device
                audioIn = PsychPortAudio('GetAudioData', pa_master, op.audio_frame_size / op.audio_sample_rate);

                if isempty(audioIn)
                    pause(0.001);
                    continue;
                end

                % Apply fractional delay processing
                delayed = vfd(audioIn, delay_samples);

                % Apply gain and clip signal
                audioOut = max(min(op.audio_playback_gain * delayed, 1), -1);

                % Output to slave device buffer
                PsychPortAudio('FillBuffer', pa_slave3, audioOut);

                % Record lag for diagnostics
                lag = max((GetSecs - tStart)*1000 - (op.audio_frame_size/op.audio_sample_rate*1000), 0);
                lagBuffer(lagIndex) = lag;
                lagIndex = mod(lagIndex, 5000) + 1;
                lagCount = min(lagCount + 1, 5000);

                frameCounter = frameCounter + 1;
                if mod(frameCounter, 10) == 0
                    Screen('Flip', window, 0, 1);
                end
                pause(0.001);
            end
        else
            % Non-speak or no delay → simple wait for sentence duration
            WaitSecs(op.text_stim_dur);
        end

        % Stop DAF playback and log trigger
        PsychPortAudio('Stop', pa_slave3, 1, 1);
        vfd.reset();
        dafOffTime = GetSecs();
        code = TRIG_DAF;
        log_event(eventFile, cfg.DIGOUT, dafOffTime, [], [], trialType, [], code, 'DAF Off', flipSyncState);

        % Show fixation cross for ITI
        Screen('FillRect', window, op.bg_color);
        DrawFormattedText(window, '*', 'center', 'center', [0 0 0]);
        Screen('Flip', window);
        WaitSecs(op.fix_cross_dur);

        % Wait for subject key press and log event
        [keyPressTime, keyCode] = KbWait(cfg.KEYBOARD_ID, 2);
        code = TRIG_TRIAL + TRIG_KEY;
        log_event(eventFile, cfg.DIGOUT, keyPressTime, [], [], trialType, [], code, 'Key Press', flipSyncState);

        % Randomize and wait ITI duration
        ItiDuration = ITI_S(1) + rand() * 0.5;
        ItiOnsetTime = keyPressTime + KEYPRESS_S;
        flipSyncState = ~flipSyncState;
        ItiOnsetTime = WaitSecs('UntilTime', ItiOnsetTime);
        code = TRIG_ITI;
        log_event(eventFile, cfg.DIGOUT, ItiOnsetTime, ItiDuration, [], trialType, [], code, 'ITI', flipSyncState);

        % Display trial completion summary
        trialDuration = keyPressTime - startRunTime;
        fprintf('Trial %2i / %i completed at %02d:%02d \n', idxTrial, nTrials, floor(trialDuration/60), round(mod(trialDuration,60)));
    end

%%
log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero', 0); 

% end
flipSyncState = ~flipSyncState;
mesageTime = GetSecs();
log_event(eventFile, cfg.DIGOUT, mesageTime, [], [], [], [], 0, 'End Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n',cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));
fprintf('\nRUN ID: %i\n',cfg.RUN_ID);

WaitSecs(2);

clear onCleanupTasks