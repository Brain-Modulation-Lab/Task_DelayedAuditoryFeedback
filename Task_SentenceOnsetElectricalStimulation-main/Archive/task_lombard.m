function task_lombard(cfg)
% Lombard effect task 
% Brain Modulation Lab, Massachusetts General Hospital
%
% This scripts implements a 'Lombard effect' sentence repetition task. 
% Sentences selected from the Harvard Sentences Set are presented on
% screen and auditorily with different levels of background noise. 
% 
% The same sentences are repeated in random order in blocks with a constant noise condition.
% The order of the blocks is pseudo-randomized, ensuring the experiment is
% balanced every four bocks. 
% 
% The experiment is experimenter-paced or self-paced. 
%   SPACEBAR: Advances to the next trial
%   ESCAPE: Ends experiment
%   + or -: Modulates audio volume keeping a log of the change (use only if
%   necessary)
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
%
% OUTPUT: Log file with all output to the console, Trial file containing
% description of each trial in the run and Event file containing precise
% timing of all events in the run. 


%% Task specific parameters
DB_SENTENCES = 'sentence.csv'; %file name for table with all sentences 

% noise parameters
NOISE_WAV1 = 'Multitalker_Speech_Babble_70dB.wav';
NOISE_CROSSFADE_S = 1; %Duration in secconds of noise crossfade 
NOISE_CROSSFADE_STEP_N = 30; %number of steps used for crossfade 
NOISE_CROSSFADE_STEP_S = NOISE_CROSSFADE_S/NOISE_CROSSFADE_STEP_N;

% sentence presentation parameters
SENTENCE_FONT_SIZE = round(46 * cfg.SCALE_FONT);% 62  ; %font size for presentation
SENTENCE_WRAPAT_MAX = 65 ; %max char per line for sentences
SENTENCE_WRAPAT_MIN = 28 ; %max char per line for sentences
SENTENCE_COLOR = [255 255 255]; %colot for sentence text
SENTENCE_GO_COLOR =  [45 150 69]; % RGB colot of GO text

% Fixation Cross ITI parameters
FIXCROSS_ITI_COLOR = [255 255 255]; % RGB color of ITI fixation cross
FIXCROSS_SIZE = 50; %size of fixation cross
FIXCROSS_ITI_S = [1, 1]; % duration range in secconds of ITI
SPACER_VISUAL_AUDIO_S = [0,0]; %duration range for visual sentence onset to audio sentence onset
SPACER_AUDIO_GO_S = [0.25, 0.75]; %duration range for end of audio to GO signal. 
KEYPRESS_S = 0.1; %duration of key press event 

% Welcome message
WELCOME_MESSAGE = {'PLEASE REPEAT ALOUD THE FOLLOWING SENTENCES.\n          WAIT FOR SENTENCES TO TURN               TO START.             ',...
                   ' \n                                     GREEN'}; 
WELCOME_MESSAGE_COLOR = {SENTENCE_COLOR,SENTENCE_GO_COLOR};
WELCOME_MESSAGE_FONT_SIZE =  round(34 * cfg.SCALE_FONT); %45; %font size for presentation
THANKYOU_MESSAGE = 'END OF TASK\nThank you!';
PAUSE_MESSAGE = '<<< Let''s take a short rest >>>';

%trigger codes
TRIG_FIXCROSS = 1;
TRIG_AUDITORY = 2;
TRIG_VISUAL = 4;
TRIG_GO = 8;
TRIG_KEY = 16;
TRIG_VOLUME = 32;
TRIG_UP = 64;
TRIG_NOISE = 128;

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
keyCodeRequestPause = KbName('R');
keyCodePause = KbName('P');
keyCodeUp = KbName('=+');
keyCodeDown = KbName('-_');
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
onCleanupTasks{18} = onCleanup(@() PsychPortAudio('Close', pa_master));

% starting master device
pa_repetitions = 0;
pa_when = 0;
pa_waitForStart = 0;
PsychPortAudio('Start', pa_master, pa_repetitions, pa_when, pa_waitForStart);
onCleanupTasks{17} = onCleanup(@() PsychPortAudio('Stop', pa_master));

% Initializing Screen
fprintf('Initializing Screen...'); 
AssertOpenGL()
% PsychDefaultSetup(2);
onCleanupTasks{16} = onCleanup(@() Priority(0));
Screen('Preference','Verbosity',3); %screen
screens = Screen('Screens');
if isempty(cfg.SCREEN_ID)
    cfg.SCREEN_ID = max(screens);
end
white = WhiteIndex(cfg.SCREEN_ID);
black = BlackIndex(cfg.SCREEN_ID);

% open black window
if cfg.SKIP_SYNC_TEST
    fprintf('skipping sync test');
	Screen('Preference', 'VisualDebugLevel', 0);
    Screen('Preference', 'SkipSyncTests', 1);
	Screen('Preference', 'SuppressAllWarnings', 1);
end
if ~isempty(cfg.CONSERVE_VRAM_MODE)
    Screen('Preference','ConserveVRAM',cfg.CONSERVE_VRAM_MODE);
end
Screen('Preference', 'TextRenderer', 0);
onCleanupTasks{15} = onCleanup(@() Screen('Preference', 'TextRenderer', 1));
[ptb_window, ptb_window_rect] = Screen('OpenWindow', cfg.SCREEN_ID, black);
onCleanupTasks{14} = onCleanup(@() Screen('Close', ptb_window));
Screen('TextFont', ptb_window, 'Helvetica');
fprintf('done\n'); 
flipSyncState=0;

%% Embedding de-indetified metadata into pairs of label and value triggers
log_metadata(cfg,eventFile);

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

% checking task's stimuli path
pathNoiseWav1 = [cfg.PATH_TASK filesep 'Stimuli' filesep NOISE_WAV1];
assert(isfolder(cfg.PATH_TASK),'No task directory. Check PATH_TASK.');
assert(isfile(pathNoiseWav1),'Audio noise 1 file %s not found', pathNoiseWav1);

% loading table with all sentences
dbSentences = readtable([cfg.PATH_TASK filesep 'Stimuli' filesep DB_SENTENCES],'Delimiter',',','FileType','text');    

% checking for table with randomized sentences for each trial of this run
if isfile(cfg.TRIAL_FILENAME)
    dbTrials = readtable(cfg.TRIAL_FILENAME,'Delimiter','\t','FileType','text');
else
    %randomizing sentences over conditions and saving run table
    cfg1=[];
    cfg1.db_sentences = dbSentences;
    cfg1.n_noise_conditions = 1;
    cfg1.n_repetitions = 4;
    cfg1.n_rep_balance_block = 1;
    %cfg1.block = true;
    cfg1.block1_silent = true;
    dbTrials = randomize_sentences(cfg1);
    writetable(dbTrials,cfg.TRIAL_FILENAME,'Delimiter','\t','FileType','text');
end
dbTrials.noise1(:) = dbTrials.noise_type == 1;

%% Starting noise audio with 0 volume
fprintf('Loading noise audio file...\n')
[noiseAudio1, noiseAudioFs1] = psychwavread(pathNoiseWav1);

% verifying output frequency and resampling
pa_master_status = PsychPortAudio('GetStatus', pa_master);
pa_master_Fs = pa_master_status.SampleRate;
if pa_master_Fs ~= noiseAudioFs1
    fprintf('Resampling noise audio 1...\n')
    noiseAudio1=resample(noiseAudio1,pa_master_Fs,noiseAudioFs1);
end

% converting to stereo row vectors 
noiseAudio1 = [noiseAudio1(:,1)';noiseAudio1(:,1)'];

fprintf('Loading sentences audio files...\n')
sentenceIds = unique(dbSentences.sentence_id);
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

% Opening slave device
pa_mode = 1; %1 == sound playback only;
pa_channels = 2; %playing as stereo, converting to mono by hardware connector
pa_slave1 = PsychPortAudio('OpenSlave', pa_master, pa_mode, pa_channels);
onCleanupTasks{10} = onCleanup(@() PsychPortAudio('Close', pa_slave1));

% filling noise buffers
fprintf('Filling noise audio buffers...\n')
PsychPortAudio('FillBuffer', pa_slave1, noiseAudio1);

% setting volume to 0 for fading in 
volumeMax = cfg.AUDIO_AMP; %fraction of max output (some room to increase volume if requried)
noiseVolumeStep = 0; %current position, integer from 0 to NOISE_CROSSFADE_STEP_N
PsychPortAudio('Volume', pa_slave1, volumeMax * noiseVolumeStep/NOISE_CROSSFADE_STEP_N);

% starting audio on slave
pa_repetitions = 0; %Infinite repetition 
pa_when = 0;
pa_waitForStart = 1;
noiseStart = PsychPortAudio('Start', pa_slave1, pa_repetitions, pa_when, pa_waitForStart);
log_event(eventFile, cfg.DIGOUT, noiseStart, [], [], [], [], TRIG_AUDITORY + TRIG_NOISE, 'Noise Start',flipSyncState);
onCleanupTasks{8} = onCleanup(@() PsychPortAudio('Stop', pa_slave1));

fprintf('Volume = %i%%\n', round(100*volumeMax));

% creating slave audio channel for sentences
pa_slave3 = PsychPortAudio('OpenSlave', pa_master, pa_mode, pa_channels);
onCleanupTasks{7} = onCleanup(@() PsychPortAudio('Close', pa_slave3));
onCleanupTasks{6} = onCleanup(@() fprintf('Cleaning up.\n'));

% loading first trial sentence
PsychPortAudio('FillBuffer', pa_slave3, sentenceAudio{dbTrials.sentence_id(1)});

fprintf('\nPress any key to advance trial. \nPress ESCAPE to end run.\nPress + and - to change volume.\n');
fprintf('Press R to request a pause at the next preferred pausing point.\nPress P to pause immediately.\n');
fprintf('\nStarting run %i at %s \n',cfg.RUN_ID,datestr(now,'HH:MM:SS am'));
fprintf('RUN ID: %i\n\n',cfg.RUN_ID);
% commandwindow;
% WaitSecs(0.1);

HideCursor(ptb_window);
onCleanupTasks{5} = onCleanup(@() ShowCursor([],ptb_window));

% Welcome message and instructions
Screen('TextSize', ptb_window, WELCOME_MESSAGE_FONT_SIZE);
for i=1:numel(WELCOME_MESSAGE_COLOR)
    DrawFormattedText(ptb_window, WELCOME_MESSAGE{i}, 'center', ptb_window_rect(4)/2, WELCOME_MESSAGE_COLOR{i},[],[],[],2);
end
flipSyncState = ~flipSyncState;
Screen('FillRect', ptb_window, cfg.SCREEN_SYNC_COLOR .* flipSyncState, cfg.SCREEN_SYNC_RECT);
[~, welcomeMesageTime] = Screen('Flip',ptb_window);
log_event(eventFile, cfg.DIGOUT, welcomeMesageTime, [], [], [], [], 0, 'Welcome Message', flipSyncState);

% waiting for next trial keypress
[keyPressTime, keyCode] = KbWait(cfg.KEYBOARD_ID, 2);
log_event(eventFile, cfg.DIGOUT, keyPressTime, [], [], [], [], TRIG_KEY, 'Key Pressed', flipSyncState);
startRunTime = keyPressTime;

if any(ismember(find(keyCode),keyCodeEscape))
    code = TRIG_KEY + TRIG_UP;
    log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], code, 'Escape', flipSyncState);
    fprintf("Escape key detected, ending run.\n");
    return
end

% setting ITI fixation cross
Screen('TextSize', ptb_window, FIXCROSS_SIZE);
DrawFormattedText(ptb_window, '+', 'center', ptb_window_rect(4)/2, FIXCROSS_ITI_COLOR);
flipSyncState = ~flipSyncState;
Screen('FillRect', ptb_window, cfg.SCREEN_SYNC_COLOR .* flipSyncState, cfg.SCREEN_SYNC_RECT);
[~, fixcrossItiOnsetTime] = Screen('Flip',ptb_window);
fixcrossDuration = FIXCROSS_ITI_S(1) + (FIXCROSS_ITI_S(2) - FIXCROSS_ITI_S(1)) .* rand(1);    
log_event(eventFile, cfg.DIGOUT, fixcrossItiOnsetTime, fixcrossDuration, [], [], [], TRIG_FIXCROSS, 'Fixation Cross', flipSyncState);

%% Trial loop
nTrials = height(dbTrials);
pause_requested = 0;
for idxTrial = 1:nTrials
    
	trialType = num2str(dbTrials.noise_type(idxTrial)); %numeric representation of type of trial
    
    % Control volume from script and log changes
    while any(ismember(find(keyCode),[keyCodeUp, keyCodeDown]))
        if any(ismember(find(keyCode), keyCodeUp))
            volumeMax = volumeMax * 1.1220; %increasing in 1dB
            code = TRIG_FIXCROSS + TRIG_NOISE * (noiseVolumeStep>0) + TRIG_KEY + TRIG_VOLUME + TRIG_UP;
            fprintf('+1dB, ');
        else
            volumeMax = volumeMax / 1.1220; %decreasing in 1dB;
            code = TRIG_FIXCROSS + TRIG_NOISE * (noiseVolumeStep>0) + TRIG_KEY + TRIG_VOLUME;
            fprintf('-1dB, ');
        end
        fprintf('Volume = %i%%\n', round(100*volumeMax));
        PsychPortAudio('Volume', pa_slave1, volumeMax * noiseVolumeStep/NOISE_CROSSFADE_STEP_N);
        log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], code, sprintf('Volume = %i',round(100*volumeMax)), flipSyncState);
        WaitSecs(KEYPRESS_S);
        code = TRIG_FIXCROSS + TRIG_NOISE * (noiseVolumeStep>0);
        log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], code, "Key Press End", flipSyncState);
        [keyPressTime, keyCode] = KbWait(cfg.KEYBOARD_ID, 2);
    end
    
    %terminating task if escape key has been pressed
    if any(ismember(find(keyCode),keyCodeEscape))
        code = TRIG_FIXCROSS + TRIG_NOISE .* (noiseVolumeStep>0) + TRIG_KEY + TRIG_UP;
        log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], code, 'Escape', flipSyncState);
        fprintf("Escape key detected, ending run.\n");
        break
    end
    
    %requestig pause at next pause point
    if any(ismember(find(keyCode), keyCodeRequestPause))
        code = TRIG_FIXCROSS + TRIG_NOISE .* (noiseVolumeStep>0) + TRIG_KEY + TRIG_UP;
        log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], code, 'Pause Requested', flipSyncState);
        fprintf("Pause requested, waiting for suitable pause point. Press P to mute in next trial.\n");
        pause_requested = 1;       
    end
    
    %pausing if requested
    if any(ismember(find(keyCode), keyCodePause)) || (pause_requested == 1 && dbTrials.pause_point(idxTrial) == 1)

        code = TRIG_FIXCROSS + TRIG_NOISE .* (noiseVolumeStep>0) + TRIG_UP;
        if any(ismember(find(keyCode), [keyCodePause keyCodeRequestPause]))
            code = code + TRIG_KEY;
        end
        log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], code, 'Mute/pause', flipSyncState);
        fprintf("Muting noise and pausing.\n");
        
        Screen('TextSize', ptb_window, WELCOME_MESSAGE_FONT_SIZE);
        DrawFormattedText(ptb_window, PAUSE_MESSAGE, 'center', ptb_window_rect(4)/2, SENTENCE_COLOR,[],[],[],2);
        flipSyncState = ~flipSyncState;
        Screen('FillRect', ptb_window, cfg.SCREEN_SYNC_COLOR .* flipSyncState, cfg.SCREEN_SYNC_RECT);
        [~, mesageTime] = Screen('Flip',ptb_window);
        log_event(eventFile, cfg.DIGOUT, mesageTime, [], [], [], [], 0, 'Pause Message', flipSyncState);
        
        noiseVolumeStepDelta = (0 - round(noiseVolumeStep/NOISE_CROSSFADE_STEP_N));
        if noiseVolumeStepDelta == -1 
            fprintf('Fading noise out...');
            code = TRIG_FIXCROSS + TRIG_NOISE * (noiseVolumeStep>0);
            log_event(eventFile, cfg.DIGOUT, [], NOISE_CROSSFADE_S, [], [], NOISE_WAV1, code, 'Fading Noise Out', flipSyncState);
            for i=1:NOISE_CROSSFADE_STEP_N
                WaitSecs('YieldSecs',NOISE_CROSSFADE_STEP_S); %playing nicely with other processes
                noiseVolumeStep = noiseVolumeStep + noiseVolumeStepDelta;
                PsychPortAudio('Volume', pa_slave1, volumeMax * noiseVolumeStep/NOISE_CROSSFADE_STEP_N);
            end
            code = TRIG_FIXCROSS;
            log_event(eventFile, cfg.DIGOUT, [], [], [], [], NOISE_WAV1, code, 'Fading Noise Complete', flipSyncState);
        end
        log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero', 0);
        
        pause_requested = 0; 
        
        fprintf("Press any key to continue or ESC to exit.\n");
        [keyPressTime, keyCode] = KbWait(cfg.KEYBOARD_ID, 2);
        if any(ismember(find(keyCode),keyCodeEscape))
            code = TRIG_FIXCROSS + TRIG_NOISE .* (noiseVolumeStep>0) + TRIG_KEY + TRIG_UP;
            log_event(eventFile, cfg.DIGOUT, keyPressTime, [], [], [], [], code, 'Escape', flipSyncState);
            fprintf("Escape key detected, ending run.\n");
            break
        end
        
        Screen('TextSize', ptb_window, FIXCROSS_SIZE);
        DrawFormattedText(ptb_window, '+', 'center', ptb_window_rect(4)/2, FIXCROSS_ITI_COLOR);
        flipSyncState = ~flipSyncState;
        Screen('FillRect', ptb_window, cfg.SCREEN_SYNC_COLOR .* flipSyncState, cfg.SCREEN_SYNC_RECT);
        [~, fixcrossItiOnsetTime] = Screen('Flip',ptb_window);
        code = TRIG_FIXCROSS;
        log_event(eventFile, cfg.DIGOUT, fixcrossItiOnsetTime, fixcrossDuration, [], trialType, [], code, 'Fixation Cross', flipSyncState);

    end
    
    noiseVolumeStepDelta = (dbTrials.noise1(idxTrial) - round(noiseVolumeStep/NOISE_CROSSFADE_STEP_N));
    if noiseVolumeStepDelta ~= 0 
        code = TRIG_FIXCROSS + TRIG_NOISE;
        if noiseVolumeStepDelta == 1
            fprintf('Fading noise in...');
            log_event(eventFile, cfg.DIGOUT, [], NOISE_CROSSFADE_S, [], [], NOISE_WAV1, code, 'Fading Noise In', flipSyncState);
        elseif noiseVolumeStepDelta == -1
            fprintf('Fading noise out...');
            log_event(eventFile, cfg.DIGOUT, [], NOISE_CROSSFADE_S, [], [], NOISE_WAV1, code, 'Fading Noise Out', flipSyncState);
        end
        % crossfading noise
        for i=1:NOISE_CROSSFADE_STEP_N
            WaitSecs('YieldSecs',NOISE_CROSSFADE_STEP_S); %playing nicely with other processes
            noiseVolumeStep = noiseVolumeStep + noiseVolumeStepDelta;
            PsychPortAudio('Volume', pa_slave1, volumeMax * noiseVolumeStep/NOISE_CROSSFADE_STEP_N);
        end
        fprintf('done\n');    
        code = TRIG_FIXCROSS + TRIG_NOISE * (noiseVolumeStep>0);
        log_event(eventFile, cfg.DIGOUT, [], [], [], [], NOISE_WAV1, code, 'Fading Noise Complete', flipSyncState);
    end

    %calculating random delays for this trial
	spacerVisualAudio = SPACER_VISUAL_AUDIO_S(1) + (SPACER_VISUAL_AUDIO_S(2) - SPACER_VISUAL_AUDIO_S(1)) .* rand(1);
    spacerAudioGo = SPACER_AUDIO_GO_S(1) + (SPACER_AUDIO_GO_S(2) - SPACER_AUDIO_GO_S(1)) .* rand(1);
    
    
    % prepearing sentence in the background and displaying at correct time
    Screen('TextSize', ptb_window, SENTENCE_FONT_SIZE);
    if strlength(dbTrials.sentence{idxTrial}) >= SENTENCE_WRAPAT_MAX
        sentenceWrapAt = SENTENCE_WRAPAT_MIN;
    else
        sentenceWrapAt = SENTENCE_WRAPAT_MAX;
    end
    DrawFormattedText(ptb_window, dbTrials.sentence{idxTrial}, 'center', ptb_window_rect(4)/2, SENTENCE_COLOR, sentenceWrapAt);
    
    % visual sentence onset
    flipSyncState = ~flipSyncState;
    Screen('FillRect', ptb_window, cfg.SCREEN_SYNC_COLOR .* flipSyncState, cfg.SCREEN_SYNC_RECT);
    [~, SentenceOnsetTime] = Screen('Flip', ptb_window, fixcrossItiOnsetTime + fixcrossDuration);
    code = TRIG_VISUAL + TRIG_NOISE .* (noiseVolumeStep>0);
	log_event(eventFile, cfg.DIGOUT, SentenceOnsetTime, [], [], trialType, dbTrials.file_text{idxTrial}, code, 'Sentence Visual Onset',flipSyncState);
    
    % starting audio on slave
	sentenceId = dbTrials.sentence_id(idxTrial);
    pa_repetitions = 1; 
    pa_when = SentenceOnsetTime + spacerVisualAudio;
    pa_waitForStart = 1; %get time of audio start
	PsychPortAudio('Volume', pa_slave3, volumeMax);
    sentenceStart = PsychPortAudio('Start', pa_slave3, pa_repetitions, pa_when, pa_waitForStart);
	code = TRIG_VISUAL + TRIG_AUDITORY + TRIG_NOISE .* (noiseVolumeStep>0);
    log_event(eventFile, cfg.DIGOUT, sentenceStart, sentenceDuration(sentenceId), [], trialType, dbTrials.file_audio{idxTrial}, code, 'Sentence Audio', flipSyncState);
    
    % Waiting until end of sentence
    WaitSecs('UntilTime', sentenceStart + sentenceDuration(sentenceId));
	code = TRIG_VISUAL + TRIG_NOISE .* (noiseVolumeStep>0);
    % MRR stimulate at speach onset 
    m_006_speech_onset_detection_and_stimulation_test(cfg);
    %%%%%%%%

    log_event(eventFile, cfg.DIGOUT, sentenceStart + sentenceDuration(sentenceId), [], [], trialType, [], code, 'End Sentence Audio', flipSyncState);
    
    % drawing GO cue sentence in the background
	DrawFormattedText(ptb_window, dbTrials.sentence{idxTrial}, 'center', ptb_window_rect(4)/2, SENTENCE_GO_COLOR, sentenceWrapAt);
    
    %Wait until end of sentence for GO cue
    flipSyncState = ~flipSyncState;
    Screen('FillRect', ptb_window, cfg.SCREEN_SYNC_COLOR .* flipSyncState, cfg.SCREEN_SYNC_RECT);
	[~, SentenceGoOnsetTime] = Screen('Flip', ptb_window, sentenceStart + sentenceDuration(sentenceId) + spacerAudioGo);
	code = TRIG_VISUAL + TRIG_GO + TRIG_NOISE .* (noiseVolumeStep>0);
	log_event(eventFile, cfg.DIGOUT, SentenceGoOnsetTime, [], [], trialType, dbTrials.file_text{idxTrial}, code, 'Go', flipSyncState);

	% loading audio buffer for next sentence
	if idxTrial < nTrials
        PsychPortAudio('FillBuffer', pa_slave3, sentenceAudio{dbTrials.sentence_id(idxTrial+1)});
    end
    
	% waiting for next trial keypress
    [keyPressTime, keyCode] = KbWait(cfg.KEYBOARD_ID, 2);
	code = TRIG_VISUAL + TRIG_KEY + TRIG_NOISE .* (noiseVolumeStep>0);
    log_event(eventFile, cfg.DIGOUT, keyPressTime, [], [], trialType, [], code, 'Key Press', flipSyncState);
    
    % message to experimenter
    trialDuration = keyPressTime - startRunTime;
    fprintf('Trial %2i / %i copleted at %02d:%02d \n', idxTrial, nTrials, floor(trialDuration/60),round(mod(trialDuration,60)));

    % calculating delay for fixation cross
    fixcrossDuration = FIXCROSS_ITI_S(1) + (FIXCROSS_ITI_S(2) - FIXCROSS_ITI_S(1)) .* rand(1);
    
	% setting ITI fixation cross
    fixcrossItiOnsetTime = keyPressTime + KEYPRESS_S;
    Screen('TextSize', ptb_window, FIXCROSS_SIZE);
    DrawFormattedText(ptb_window, '+', 'center', ptb_window_rect(4)/2, FIXCROSS_ITI_COLOR);
	flipSyncState = ~flipSyncState;
    Screen('FillRect', ptb_window, cfg.SCREEN_SYNC_COLOR .* flipSyncState, cfg.SCREEN_SYNC_RECT);
    WaitSecs('UntilTime',fixcrossItiOnsetTime);
    [~, fixcrossItiOnsetTime] = Screen('Flip',ptb_window);
	code = TRIG_FIXCROSS + TRIG_NOISE .* (noiseVolumeStep>0);
    log_event(eventFile, cfg.DIGOUT, fixcrossItiOnsetTime, fixcrossDuration, [], trialType, [], code, 'Fixation Cross', flipSyncState);
             
end

noiseVolumeStepDelta = (0 - round(noiseVolumeStep/NOISE_CROSSFADE_STEP_N));
if noiseVolumeStepDelta == -1 
	fprintf('Fading noise out...');
    code = TRIG_FIXCROSS + TRIG_NOISE * (noiseVolumeStep>0);
    log_event(eventFile, cfg.DIGOUT, [], NOISE_CROSSFADE_S, [], [], NOISE_WAV1, code, 'Fading Noise Out', flipSyncState);
    for i=1:NOISE_CROSSFADE_STEP_N
        WaitSecs('YieldSecs',NOISE_CROSSFADE_STEP_S); %playing nicely with other processes
        noiseVolumeStep = noiseVolumeStep + noiseVolumeStepDelta;
        PsychPortAudio('Volume', pa_slave1, volumeMax * noiseVolumeStep/NOISE_CROSSFADE_STEP_N);
    end
	code = TRIG_FIXCROSS;
    log_event(eventFile, cfg.DIGOUT, [], [], [], [], NOISE_WAV1, code, 'Fading Noise Complete', flipSyncState);
end
log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero', 0); 

% Thank you message
Screen('TextSize', ptb_window, WELCOME_MESSAGE_FONT_SIZE);
DrawFormattedText(ptb_window, THANKYOU_MESSAGE, 'center', ptb_window_rect(4)/2, SENTENCE_COLOR,[],[],[],2);
flipSyncState = ~flipSyncState;
Screen('FillRect', ptb_window, cfg.SCREEN_SYNC_COLOR .* flipSyncState, cfg.SCREEN_SYNC_RECT);
[~, mesageTime] = Screen('Flip',ptb_window);
log_event(eventFile, cfg.DIGOUT, mesageTime, [], [], [], [], 0, 'Thank you Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n',cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));
fprintf('\nRUN ID: %i\n',cfg.RUN_ID);

WaitSecs(2);

clear onCleanupTasks

 