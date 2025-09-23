function task_sent_onset_stim(cfg)
% Electrical stimulation during sentences task
% Brain Modulation Lab, Massachusetts General Hospital
%
% 
% The experiment is experimenter-paced or self-paced. 
%   SPACEBAR: Advances to the next trial
%   ESCAPE: Ends experiment
%
% INPUT: cfg, configuration structure with the following fields:
%   cfg.SUBJECT             str, subject identifier
%   cfg.SESSION_LABEL       str, session label {'test','training','preop','intraop','emu'}
%   cfg.TASK                str, task name
%   cfg.TASK_VERSION        int, task version
%   cfg.PATH_TASK           str, path to task folder Stimuli folder
%   cfg.LOG_FILENAME        str, full filename (with path) to log file. 
%   cfg.EVENT_FILENAME      str, full filename (with path) to BIDS events file.  
%   cfg.TRIAL_FILENAME      str, full filename (with path) to table specifying the run's trials
%   cfg.KEYBOARD_ID         int, preferred keyboard by ID
%   cfg.AUDIO_ID            int, preferred audio device ID
%   cfg.AUDIO_AMP           float, initial audio amplitude. 
%   cfg.SCREEN_ID           int, preferred screen ID 
%   cfg.SCALE_FONT          float, scaling factor for font
%   cfg.SKIP_SYNC_TEST      bool, should screen synchronization test be skipped? 
%   cfg.CONSERVE_VRAM_MODE	int, Psvchtoolbox ConserveVRAM Screen preference code
%   cfg.SCREEN_SYNC_COLOR   int(3), color of the corner square used for synchronization
%   cfg.SCREEN_SYNC_RECT    int(4), rectangle used for screen synchronization
%   cfg.DIGOUT              digital out parameter(s) to be passed to log_event function
%                             for Ripple intraop rig: bool indicating if Nomad is connected
%                             for Cash Lab rig it is a structure with fields
%                               cfg.DIGOUT.portObj - io64 object
%                               cfg.DIGOUT.portAddress - address of port
%   cfg.GO_BEEP_AMP
%   cfg.AUDIO_DEVICE
%   cfg.DB_SENTENCES
%   cfg.PA_RECORDER_HANDLE
%   cfg.DETECTION_OPS
%
% OUTPUT: Log file with all output to the console, Trial file containing
% description of each trial in the run and Event file containing precise
% timing of all events in the run. 


%% Task specific parameters

% Fixation Cross ITI parameters
ITI_S = [1, 1]; % duration range in secconds of ITI
SPACER_VISUAL_AUDIO_S = [0,0]; %duration range for visual sentence onset to audio sentence onset
SPACER_AUDIO_GO_S = [0.25, 0.75]; %duration range for end of audio to GO signal. 
SPACER_AUDIO_GO_TO_DETECTION_ONSET = 0.15; %buffer between end of GO signal and begginging of detection
SPACER_AUDIO_GO_TO_STIMULATION = SPACER_AUDIO_GO_TO_DETECTION_ONSET; %buffer between end of GO signal and begginging of detection

KEYPRESS_S = 0.1; %duration of key press event 

volumeMax = 1; 

% Go cue % audio to play as START cue
start_cue_audio_file = [cfg.PATH_TASK filesep 'Stimuli' filesep 'beep.wav']; 
GO_BEEP_AMP = cfg.GO_BEEP_AMP;

% Welcome message
WELCOME_MESSAGE = {'PLEASE REPEAT ALOUD THE FOLLOWING SENTENCES AFTER THE BEEP.'}; 

%trigger codes
TRIG_ITI = 1;
TRIG_AUDITORY = 2;
TRIG_TRIAL = 4;
TRIG_GO = 8;
TRIG_KEY = 16;
TRIG_STIM = 32;

%% Read trials table
%dbTrials = readtable(cfg.TRIAL_FILENAME,'Delimiter','\t','FileType','text');
dbTrials = cfg.TRIAL_TABLE;

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

% Initialize Sound
fprintf('Initializing Sound...\n'); 
PsychDefaultSetup(2);
InitializePsychSound; 

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

%% Preload go-cue audio
fprintf('Loading cue audio file...\n')
[go_beep, beep_Fs] = psychwavread(start_cue_audio_file);
% verifying output frequency and resampling
if pa_handle_Fs ~= beep_Fs
    fprintf('Resampling beep audio...\n')
    go_beep=resample(go_beep,pa_handle_Fs,beep_Fs);
    beep_Fs = pa_handle_Fs;
end
% converting to stereo row vectors 
go_beep = [go_beep(:,1)';go_beep(:,1)'] .* GO_BEEP_AMP .* cfg.AUDIO_AMP;
go_beep_duration = size(go_beep,2) ./ beep_Fs;

%testing triggers
for i = 1:5
    log_event(eventFile, cfg.DIGOUT, [], 0.25, [], [], [], 255, 'Trigger test',1);
    WaitSecs('YieldSecs',0.25);
    log_event(eventFile, cfg.DIGOUT, [], 0.25, [], [], [], 0, 'Trigger test',0);
    WaitSecs('YieldSecs',0.25);            
end

%% ******************************************************************** %%
%                         TASK SPECIFIC SECTION                          %
%  ********************************************************************  %
%% 
fprintf('%s Task run is starting...\n', cfg.TASK);

% verifying output frequency and resampling
pa_master_status = PsychPortAudio('GetStatus', pa_master);
pa_master_Fs = pa_master_status.SampleRate;

fprintf('Loading sentences audio files...\n');
% loading table with all sentences
dbSentences = readtable([cfg.PATH_TASK filesep 'Stimuli' filesep cfg.DB_SENTENCES],'Delimiter',',','FileType','text');    
sentenceIds = unique(dbSentences.sentence_id);
% the following assert doesn't make sense after I [Latane Bullock] removed 
% sentence_id==5 and sentence_id==6 to reduce the number of sentences
% [update] I updated sentence_id to be 1,2,...8
assert(max(sentenceIds) == height(dbSentences) && length(sentenceIds) == height(dbSentences),'incorrect sentence_id');
sentenceAudio = cell(height(dbSentences),1);
sentenceDuration = zeros(height(dbSentences),1);
for i=1:height(dbSentences)
    [audio, Fs] = psychwavread([cfg.PATH_TASK filesep 'Stimuli' filesep dbSentences.file_audio{i}]);
    sentenceDuration(i) = size(audio,1)/Fs;
    if pa_master_Fs ~= Fs
        audio=resample(audio,pa_master_status.SampleRate,Fs);
    end
    sentenceAudio{i} = [audio(:,1)';audio(:,1)'];
end

% creating slave audio channel for sentences
pa_slave3 = PsychPortAudio('OpenSlave', pa_master, pa_mode, pa_channels);
onCleanupTasks{7} = onCleanup(@() PsychPortAudio('Close', pa_slave3));
onCleanupTasks{6} = onCleanup(@() fprintf('Cleaning up.\n'));

% loading first trial sentence
PsychPortAudio('FillBuffer', pa_slave3, sentenceAudio{dbTrials.sentence_id(1)});

fprintf('\nPress any key to advance trial. \nPress ESCAPE to end run.\n');
fprintf('\nStarting run %i at %s \n',cfg.RUN_ID,datestr(now,'HH:MM:SS am'));
fprintf('RUN ID: %i\n\n',cfg.RUN_ID);
% commandwindow;
% WaitSecs(0.1);

% Welcome message and instructions
disp(WELCOME_MESSAGE);
flipSyncState = ~flipSyncState;
welcomeMesageTime = GetSecs();
log_event(eventFile, cfg.DIGOUT, welcomeMesageTime, [], [], [], [], 0, 'Welcome Message', flipSyncState);

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

%% Trial loop
nTrials = height(dbTrials);
% pause_requested = 0;
for idxTrial = 1:nTrials
    
    trialType = dbTrials.stim_epoch{idxTrial};
    
    %terminating task if escape key has been pressed
    if any(ismember(find(keyCode),keyCodeEscape))
        code = TRIG_ITI + TRIG_KEY;
        log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], code, 'Escape', flipSyncState);
        fprintf("Escape key detected, ending run.\n");
        break
    end

    %calculating random delays for this trial
	spacerVisualAudio = SPACER_VISUAL_AUDIO_S(1) + (SPACER_VISUAL_AUDIO_S(2) - SPACER_VISUAL_AUDIO_S(1)) .* rand(1);
    spacerAudioGo = SPACER_AUDIO_GO_S(1) + (SPACER_AUDIO_GO_S(2) - SPACER_AUDIO_GO_S(1)) .* rand(1);
    
    % visual sentence onset
    flipSyncState = ~flipSyncState;
    SentenceOnsetTime = WaitSecs('UntilTime', ItiOnsetTime + ItiDuration); 
    code = TRIG_TRIAL;
	log_event(eventFile, cfg.DIGOUT, SentenceOnsetTime, [], [], trialType, dbTrials.file_text{idxTrial}, code, 'Trial Onset', flipSyncState);
     
    % starting audio on slave
	sentenceId = dbTrials.sentence_id(idxTrial);
    pa_repetitions = 1; 
    pa_when = SentenceOnsetTime + spacerVisualAudio;
    pa_waitForStart = 1; %get time of audio start
	PsychPortAudio('Volume', pa_slave3, volumeMax);
    sentenceStart = PsychPortAudio('Start', pa_slave3, pa_repetitions, pa_when, pa_waitForStart);
	code = TRIG_TRIAL + TRIG_AUDITORY;
    log_event(eventFile, cfg.DIGOUT, sentenceStart, sentenceDuration(sentenceId), [], trialType, dbTrials.file_audio{idxTrial}, code, 'Sentence Audio', flipSyncState);
    
    % Waiting until end of sentence
    WaitSecs('UntilTime', sentenceStart + sentenceDuration(sentenceId));
	code = TRIG_TRIAL;
    log_event(eventFile, cfg.DIGOUT, sentenceStart + sentenceDuration(sentenceId), [], [], trialType, [], code, 'End Sentence Audio', flipSyncState);
    
   % loading start beep
    PsychPortAudio('FillBuffer', pa_slave3, go_beep);
    WaitSecs('UntilTime', sentenceStart + sentenceDuration(sentenceId) + spacerAudioGo);

    % Wait until end of sentence for GO cue
    flipSyncState = ~flipSyncState;
	SentenceGoOnsetTime = GetSecs();
    code = TRIG_TRIAL + TRIG_GO;
	log_event(eventFile, cfg.DIGOUT, SentenceGoOnsetTime, [], [], trialType, dbTrials.file_text{idxTrial}, code, 'Go', flipSyncState);

    % stimulate at trigger
    iTrial = table2struct(dbTrials(idxTrial,:));

    if(strcmp(cfg.SESSION_LABEL,'intraop'))
        fprintf('Stim settings | Elec: %s, Freq: %.0f Hz, TL: %.0f ms, Amp: %s mA, PW1: %d us, PW Ratio: %.1f, IPI: %d us, Label: %s\n', ...
        mat2str(iTrial.stim_elec), ...
        round(iTrial.stim_freq), ...
        round(iTrial.stim_tl), ...
        mat2str(iTrial.stim_amp), ...
        iTrial.stim_pw1, ...
        iTrial.stim_pw_ratio, ...
        iTrial.stim_ipi, ...
        iTrial.stim_label);
    end

    % Generate the GO prompt (beep)
    pa_repetitions = 1; 
    pa_when = 0;
    pa_waitForStart = 1; % get time of audio start
    audioGoTime = PsychPortAudio('Start', pa_slave3, pa_repetitions, pa_when, pa_waitForStart);
    code = TRIG_TRIAL + TRIG_GO;
    log_event(eventFile, cfg.DIGOUT, audioGoTime, go_beep_duration, [], iTrial.stim_epoch, [], code, 'Go Beep', flipSyncState);

    if strcmpi(iTrial.stim_trig, 'go')        
        WaitSecs('UntilTime', audioGoTime + go_beep_duration + SPACER_AUDIO_GO_TO_STIMULATION); %waiting until after beep ends to start stim
        WaitSecs(iTrial.stim_delay);
        fprintf('Stimulation triggered by Go cue...');
        [stim_onset, stim_duration] = ripple_stim_DBS(cfg,iTrial);
        code = TRIG_TRIAL + TRIG_STIM;
        %log_event(eventFile, cfg.DIGOUT, stim_onset, stim_duration, [], iTrial.stim_epoch, [], TRIG_STIM, 'DBS', flipSyncState);
    elseif strcmpi(iTrial.stim_trig, 'speech-onset')
        fprintf('Stimulation triggered by spech onset...');
        WaitSecs('UntilTime', audioGoTime + go_beep_duration + SPACER_AUDIO_GO_TO_DETECTION_ONSET); %avoiding self triggering by GO beep
        [level, audio_all] = speech_onset_detection(cfg.PA_RECORDER_HANDLE, cfg.DETECTION_OPS); 
        if level > cfg.DETECTION_OPS.loudness_threshold
            WaitSecs(iTrial.stim_delay);
            [stim_onset, stim_duration] = ripple_stim_DBS(cfg,iTrial);
            code = TRIG_TRIAL + TRIG_STIM;
            %log_event(eventFile, cfg.DIGOUT, stim_onset, stim_duration, [], iTrial.stim_epoch, [], TRIG_STIM, 'DBS', flipSyncState);
        else
            fprintf(' timed out at %f seconds.',cfg.DETECTION_OPS.max_dur_seconds);
            stim_onset = GetSecs();
            stim_duration = 0;
            code = TRIG_TRIAL;
            %log_event(eventFile, cfg.DIGOUT, GetSecs(), 0, [], iTrial.stim_epoch, [], 0, 'Timed out', flipSyncState);
        end
        fprintf(' level = %f (threshold = %f) ...',level,cfg.DETECTION_OPS.loudness_threshold);
        t = linspace(0, length(audio_all)/cfg.PA_RECORDER_FS , length(audio_all));
        plot(t, audio_all, 'k');
        drawnow;
        PsychPortAudio('Stop', cfg.PA_RECORDER_HANDLE);
    else
        fprintf('No stimulation in this trial...');
        stim_onset = GetSecs();
        stim_duration = 0;
        code = TRIG_TRIAL;
    end
    fprintf('done.\n');
    log_event(eventFile, cfg.DIGOUT, stim_onset, stim_duration, [], iTrial.stim_epoch, [], code, 'DBS', flipSyncState);

    %%
    
	% loading audio buffer for next sentence
	if idxTrial < nTrials
      PsychPortAudio('FillBuffer', pa_slave3, sentenceAudio{dbTrials.sentence_id(idxTrial+1)});
    end
    
	% waiting for next trial keypress
    [keyPressTime, keyCode] = KbWait(cfg.KEYBOARD_ID, 2);
	code = TRIG_TRIAL + TRIG_KEY;
    log_event(eventFile, cfg.DIGOUT, keyPressTime, [], [], trialType, [], code, 'Key Press', flipSyncState);
    
    % message to experimenter
    trialDuration = keyPressTime - startRunTime;
    fprintf('Trial %2i / %i completed at %02d:%02d \n', idxTrial, nTrials, floor(trialDuration/60),round(mod(trialDuration,60)));

    % calculating delay for fixation cross
    ItiDuration = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);
    
	% setting ITI fixation cross
    ItiOnsetTime = keyPressTime + KEYPRESS_S;
  	flipSyncState = ~flipSyncState;
    ItiOnsetTime = WaitSecs('UntilTime',ItiOnsetTime);
    code = TRIG_ITI;
    log_event(eventFile, cfg.DIGOUT, ItiOnsetTime, ItiDuration, [], trialType, [], code, 'ITI', flipSyncState);
             
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

 