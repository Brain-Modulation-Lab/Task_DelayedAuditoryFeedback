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
TRIG_ITI = 1;
TRIG_VISUAL = 2;
TRIG_TRIAL = 4;
TRIG_DAF = 8;
TRIG_KEY = 16;

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
    devices = struct2table(PsychHID('Devices'));  
    disp(devices);
end

KbName('UnifyKeyNames')
keyCodeEscape = KbName('ESCAPE');
fprintf('done\n'); 

PsychDefaultSetup(2);
InitializePsychSound; 

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
pa_mode = 3; 
pa_reqlatencyclass = 1;  
pa_freq = cfg.audio_sample_rate; 
pa_channels = 2; 
pah = PsychPortAudio('Open', cfg.AUDIO_ID, pa_mode, pa_reqlatencyclass, pa_freq, pa_channels);
onCleanupTasks{18} = onCleanup(@() PsychPortAudio('Close', pah));
PsychPortAudio('GetAudioData', pah, 60);
PsychPortAudio('Volume', pah, volumeMax .* cfg.AUDIO_AMP);
PsychPortAudio('Start', pah, 0, 0, 0);

screens = Screen('Screens');
screenId = max(screens);
[window, ~] = Screen('OpenWindow', screenId, 255);
onCleanupTasks{17} = onCleanup(@() Screen('CloseAll'));
Screen('TextSize', window, cfg.stim_font_size);

flipSyncState=0;

%% ******************************************************************** %%
%                         TASK SPECIFIC SECTION                          %
%  ********************************************************************  %
%% 
fprintf('%s Task run is starting...\n', cfg.TASK);

fprintf('\nPress ESCAPE to end run.\n');
fprintf('\nStarting run %i at %s \n',cfg.RUN_ID,datestr(now,'HH:MM:SS am'));
fprintf('RUN ID: %i\n\n',cfg.RUN_ID);

Screen('FillRect', window, 255);
DrawFormattedText(window, 'INSTRUCTIONS\n\nWhen text appears on the screen,\nRead as quickly and accurately as possible.\n\nPress any key to begin...', 'center', 'center', 0);
Screen('Flip', window);
KbWait(cfg.KEYBOARD_ID, 2);

flipSyncState = ~flipSyncState;
welcomeMesageTime = GetSecs();
log_event(eventFile, cfg.DIGOUT, welcomeMesageTime, [], [], [], [], 0, 'Instructions', flipSyncState);

flipSyncState = ~flipSyncState;
ItiOnsetTime = GetSecs();
ItiDuration = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);    
log_event(eventFile, cfg.DIGOUT, ItiOnsetTime, ItiDuration, [], [], [], TRIG_ITI, 'ITI', flipSyncState);

DAF_Trials = cfg.TRIAL_TABLE;
nTrials = height(DAF_Trials);
frameN = cfg.audio_frame_size;
Fs = cfg.audio_sample_rate;
delayMaxSamp = round(Fs * 1.2);
rb = zeros(pa_channels, delayMaxSamp + frameN);
rbLen = size(rb,2);
wPtr = 1;
startRunTime = GetSecs();

for idxTrial = 1:nTrials
    
    [isDown,~,keyCode] = KbCheck;
    if isDown && keyCode(keyCodeEscape)
        code = TRIG_ITI + TRIG_KEY;
        log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], code, 'Escape', flipSyncState);
        fprintf("Escape key detected, ending run.\n");
        break
    end

    trialType = DAF_Trials.trial_type{idxTrial};
    text_stim = DAF_Trials.text{idxTrial};
    delay_ms = double(DAF_Trials.delay_ms(idxTrial));
    delay_samples = max(0, round(Fs * (delay_ms/1000)));

    flipSyncState = ~flipSyncState;
    SentenceOnsetTime = WaitSecs('UntilTime', ItiOnsetTime + ItiDuration); 
    code = TRIG_TRIAL;
	log_event(eventFile, cfg.DIGOUT, SentenceOnsetTime, [], [], trialType, text_stim, code, 'Trial Onset', flipSyncState);

    txtWrapped = textwrap({text_stim}, cfg.stim_max_char_per_line);
    Screen('FillRect', window, 255);
    DrawFormattedText(window, strjoin(txtWrapped, '\n'), 'center', 'center', 0);
    [~, visOn] = Screen('Flip', window);

    flipSyncState = ~flipSyncState;
	code = TRIG_VISUAL;
	log_event(eventFile, cfg.DIGOUT, visOn, [], [], trialType, text_stim, code, 'Visual Onset', flipSyncState);

    flipSyncState = ~flipSyncState;
    dafOn = GetSecs();
    code = TRIG_DAF;
    log_event(eventFile, cfg.DIGOUT, dafOn, [], [], trialType, [], code, 'DAF On', flipSyncState);

    tEnd = visOn + cfg.text_stim_dur;
    while GetSecs < tEnd
        [isDown,~,keyCode] = KbCheck;
        if isDown && keyCode(keyCodeEscape)
            break
        end
        [audiodata, ~, ~] = PsychPortAudio('GetAudioData', pah, frameN/Fs);
        if ~isempty(audiodata)
            if size(audiodata,1)==1
                audiodata = [audiodata; audiodata];
            elseif size(audiodata,1)>2
                audiodata = audiodata(1:2,:);
            end
            nSamp = size(audiodata,2);
            if nSamp>0
                for k=1:nSamp
                    rb(:,wPtr) = audiodata(:,k);
                    wPtr = wPtr + 1;
                    if wPtr > rbLen
                        wPtr = 1;
                    end
                end
                startIdx = wPtr - delay_samples - nSamp;
                while startIdx <= 0
                    startIdx = startIdx + rbLen;
                end
                idxs = mod(startIdx-1:startIdx-1+nSamp-1, rbLen) + 1;
                outblk = rb(:,idxs) .* cfg.audio_playback_gain;
                outblk = max(min(outblk,1),-1);
                PsychPortAudio('FillBuffer', pah, outblk);
            end
        end
    end

    Screen('FillRect', window, 255);
    [visOff, ~] = Screen('Flip', window);
    code = TRIG_VISUAL;
    log_event(eventFile, cfg.DIGOUT, visOff, [], [], trialType, [], code, 'Visual Off', flipSyncState);

    flipSyncState = ~flipSyncState;
    dafOff = GetSecs();
    code = TRIG_DAF;
    log_event(eventFile, cfg.DIGOUT, dafOff, [], [], trialType, [], code, 'DAF Off', flipSyncState);

    ItiDuration = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);
    ItiOnsetTime = GetSecs();
    flipSyncState = ~flipSyncState;
    ItiOnsetTime = WaitSecs('UntilTime', ItiOnsetTime);
    code = TRIG_ITI;
    log_event(eventFile, cfg.DIGOUT, ItiOnsetTime, ItiDuration, [], trialType, [], code, 'ITI', flipSyncState);
             
    trialDuration = GetSecs - startRunTime;
    fprintf('Trial %2i / %i completed at %02d:%02d \n', idxTrial, nTrials, floor(trialDuration/60),round(mod(trialDuration,60)));
end

log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero', 0); 

% end
flipSyncState = ~flipSyncState;
mesageTime = GetSecs();
log_event(eventFile, cfg.DIGOUT, mesageTime, [], [], [], [], 0, 'End Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n',cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));
fprintf('\nRUN ID: %i\n',cfg.RUN_ID);

WaitSecs(2);

clear onCleanupTasks