% Intraop Launcher for DAF
%% version of launcher script before AM tried to start getting it to interface with Trellis

figure;

% --- Centralized configuration structure ---
cfg = [];

% Subject/session metadata
cfg.SUBJECT       = 'test0715';

cfg.SESSION_LABEL = 'intraop';
cfg.SESSION_LABEL = 'preop';

cfg.DATA_TYPE     = 'task';


% Task metadata (match preop naming so Task_*.m runs unchanged)
cfg.TASK          = 'daf';
cfg.TASK_VERSION  = 1;
cfg.TASK_FUNCTION = 'task_daf_nomidi.m';


% Core DAF parameters REQUIRED by Task_DelayedAuditoryFeedback
cfg.n_blocks              = 1;          % number of blocks
cfg.max_trials            = 30;         % optional cap (same default as preop)
cfg.audio_sample_rate     = 44100;      % Audio sample rate in Hz
cfg.audio_frame_size      = 128;        % block size Task_* uses for streaming; Sam's default = 128
cfg.audio_playback_gain   = 0.1;          % DAF output gain
cfg.fix_cross_dur         = 0.0;        % pre-sentence fix (Task_* uses its own ITI_S but we keep parity)
cfg.delay_dur             = 0.0;        % pre-visual onset delay 
cfg.text_stim_dur         = 12.0;       % sentence display/speaking time 
cfg.stim_font_size        = 50;         % use 50 on intraop rig
cfg.stim_max_char_per_line= 30;         % maximum number of chars per line in ortho stim figure, for text wrapping
cfg.catchRatio            = 0;          % proportion of trials which are no-speech catch trials
cfg.max_stim_repeats      = 2;          % max consecutive repeats of same stimulus within a block
cfg.max_delay_repeats     = 4;          % max consecutive repeats of same delays within a block
cfg.same_trials_across_blocks = true;   % if true: trials randomized in first block only, same order repeated across blocks

% DAF delay conditions (ms) – Task_* requires cfg.delayOptions
cfg.maxAllowedDelay_ms    = 1000;       % defensive check (mirrors preop)

% Set delay values and number of blocks according to session type
switch cfg.SESSION_LABEL
    case 'preop'
        cfg.delay_values_ms = [0 50 100 150]; % 
        cfg.n_blocks = 2;
        cfg.daf_stim_file = 'daf_sentences_preop.tsv';
    case 'intraop'
        cfg.delay_values_ms = [0 150];
%         cfg.delay_values_ms = [0 100 150 200];
        cfg.n_blocks = 4;
        cfg.daf_stim_file = 'daf_sentences_intraop.tsv';
    otherwise
        error('Unknown session label: %s', cfg.SESSION_LABEL);
end

if any(cfg.delay_values_ms > cfg.maxAllowedDelay_ms)
    error('One or more delayOptions exceed the maximum allowed delay of %d ms.', cfg.maxAllowedDelay_ms);
end

% Diagnostics / flags (used by Task_* optionally)
cfg.no_audio_debug_mode   = true;
cfg.LAG_DIAGNOSTICS       = true;

% Audio / PTB preferences

cfg.SKIP_SYNC_TEST        = 1;          % safe for bench/windowed testing; set 0 in OR if fully synced desired
cfg.CONSERVE_VRAM_MODE    = 4096;

% Choose LOCAL_TEST mode explicitly (Task_* branches on this)
% Set to false on the OR rig; set true on a laptop for quick dry-runs.
cfg.LOCAL_TEST            = 0;

% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % Paths and device configuration (point at DAF task)
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % if strcmpi(getenv('COMPUTERNAME'), 'BML-ALIENWARE2') %% intrasurgical rig laptop
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.PATH_TASK       = 'D:\Task\Task_DelayedAuditoryFeedback';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.AUDIO_DEVICE_IN = 'Focusrite USB ASIO'; 
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.AUDIO_DEVICE_OUT = 'Speakers (Radial USB Pro)';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.AUDIO_DEVICE_OUT = 'Speakers (HIFI Audio)'; % for testing without Radial USB
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % elseif ismac
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.PATH_TASK       = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.PATH_SOURCEDATA = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/stimuli';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.AUDIO_DEVICE_OUT = 'MacBook Pro Speakers';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.AUDIO_DEVICE_IN  = 'MacBook Pro Microphone';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.HOST_AUDIO_API_NAME = 'CoreAudio';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % elseif strcmpi(getenv('COMPUTERNAME'), '677-GUE-WL-0010') % Andrew Meier work laptop
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.PATH_TASK = 'C:\docs\code\Task_DelayedAuditoryFeedback'; 
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.PATH_SOURCEDATA= 'C:\ieeg_stut'; 
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     % cfg.AUDIO_DEVICE_IN = 'Headphones (WF-C500)';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.AUDIO_DEVICE_IN = 'Microphone Array (Intel® Smart Sound Technology for Digital Microphones)'; 
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     % cfg.AUDIO_DEVICE_OUT = 'Headset (WF-C500)'; 
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.AUDIO_DEVICE_OUT = 'Speakers (HIFI Audio)'; 
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % else
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.PATH_TASK       = '~/git/Task_DelayedAuditoryFeedback';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata';
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % end



% Paths and device configuration (point at DAF task)
if strcmpi(getenv('COMPUTERNAME'), 'BML-ALIENWARE2') %% intrasurgical rig laptop
    cfg.PATH_TASK       = 'D:\Task\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata';
    switch cfg.SESSION_LABEL
        case 'preop'
            cfg.AUDIO_DEVICE_IN = 'Microphone Array (Intel® Smart Sound Technology for Digital Microphones)'; % laptop onboard mic
            cfg.AUDIO_DEVICE_OUT = 'Default'; % 3.5mm audio jack for headphones
            cfg.audio_reader_driver = 'DirectSound'; 
            cfg.audio_writer_driver = 'DirectSound'; 
        case 'intraop'
            cfg.AUDIO_DEVICE_IN = 'Focusrite USB ASIO'; 
%             cfg.AUDIO_DEVICE_OUT = 'Speakers (Radial USB Pro)';r
            cfg.AUDIO_DEVICE_OUT = 'Focusrite USB ASIO'; 
            cfg.audio_reader_driver = 'ASIO'; 
            cfg.audio_writer_driver = 'ASIO'; 

    end
%     cfg.AUDIO_DEVICE_OUT = 'Speakers (HIFI Audio)'; % for testing without Radial USB
elseif ismac
    cfg.PATH_TASK       = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/';
    cfg.PATH_SOURCEDATA = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/stimuli';
    cfg.AUDIO_DEVICE_OUT = 'MacBook Pro Speakers';
    cfg.AUDIO_DEVICE_IN  = 'MacBook Pro Microphone';
    cfg.HOST_AUDIO_API_NAME = 'CoreAudio';
elseif strcmpi(getenv('COMPUTERNAME'), '677-GUE-WL-0010') % Andrew Meier work laptop
    cfg.PATH_TASK = 'C:\docs\code\Task_DelayedAuditoryFeedback'; 
    cfg.PATH_SOURCEDATA= 'C:\ieeg_stut'; 
    % cfg.AUDIO_DEVICE_IN = 'Headphones (WF-C500)';
    cfg.AUDIO_DEVICE_IN = 'Microphone Array (Intel® Smart Sound Technology for Digital Microphones)'; 
    % cfg.AUDIO_DEVICE_OUT = 'Headset (WF-C500)'; 
    cfg.AUDIO_DEVICE_OUT = 'Speakers (HIFI Audio)'; 
else
    cfg.PATH_TASK       = '~/git/Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata';
end
cfg.PATH_STIMDIR = [cfg.PATH_TASK, filesep, 'stimuli']; 



% Misc parity with preop
cfg.TEST_SOUND_S        = 10;
cfg.CALIBRATION_BEEPS_N = 5;
cfg.AUDIO_AMP           = 1;
cfg.GO_BEEP_AMP         = 0.5;
cfg.KEYBOARD_ID         = [];

% --- Warnings/PTB setup (apply prefs so toggles take effect) ---
warning('on','all'); beep off;
PsychDefaultSetup(2);
Screen('Preference','SkipSyncTests', cfg.SKIP_SYNC_TEST);
Screen('Preference','ConserveVRAM', cfg.CONSERVE_VRAM_MODE);
Screen('Preference','VisualDebugLevel', 1);
Screen('Preference','Verbosity', 3);
PsychDebugWindowConfiguration;   % windowed + alpha for bench testing (comment out on OR if undesired)

close all force; Screen('CloseAll'); % close all normal matlab figures and PTB windows

% --- Paths & output folders (match preop structure) ---
pathSub            = fullfile(cfg.PATH_SOURCEDATA, ['sub-' cfg.SUBJECT]);
pathSubSes         = fullfile(pathSub, ['ses-' cfg.SESSION_LABEL]);
pathSubSesDataType = fullfile(pathSubSes, cfg.DATA_TYPE);
pathSubSesAudio    = fullfile(pathSubSes, 'audio');

for p = {cfg.PATH_SOURCEDATA, pathSub, pathSubSes, pathSubSesDataType, pathSubSesAudio}
    if ~isfolder(p{1}), mkdir(p{1}); end
end
cfg.PATH_AUDIO = pathSubSesAudio;   % needed for AUDIO_FILENAME

% --- Run basename / filenames (integer-safe %02d) ---
fileBaseName  = ['sub-' cfg.SUBJECT '_ses-' cfg.SESSION_LABEL '_task-' cfg.TASK '_run-'];
allEventFiles = dir(fullfile(pathSubSesDataType, [fileBaseName '*_events.tsv']));
if ~isempty(allEventFiles)
    prevRunIds = regexp({allEventFiles.name}, '_run-(\d+)_', 'tokens', 'ignorecase');
    prevRunIds = cellfun(@(x) str2double(x{1,1}), prevRunIds, 'UniformOutput', true);
    runId = max(prevRunIds) + 1;
else
    runId = 1;
end

cfg.RUN_ID        = runId;
cfg.PATH_LOG      = pathSubSesDataType;
cfg.BASE_NAME     = [fileBaseName, sprintf('%02d_', runId)];
cfg.LOG_FILENAME  = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'log.txt']);
cfg.EVENT_FILENAME= fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'events.tsv']);
cfg.TRIAL_FILENAME= fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'trials.tsv']);
cfg.AUDIO_FILENAME= fullfile(cfg.PATH_AUDIO, [cfg.BASE_NAME(1:end-1) '.wav']);

% --- Start diary ---
diary(cfg.LOG_FILENAME);
onCleanupTasks = cell(10,1);
onCleanupTasks{10} = onCleanup(@() diary('off'));
disp(cfg);

% --- Optional: parallel worker for external audio recording (same pattern as preop) ---
if isempty(gcp())
    parpool('local',1);
end
workerQueueConstant = parallel.pool.Constant(@parallel.pool.PollableDataQueue);
workerQueueClient   = fetchOutputs(parfeval(@(x) x.Value, 1, workerQueueConstant));

%% Change folder 
% change to main scripts folder, like we do in Speech Motor Sequence Learning (SMSL) scripts
cd('./scripts'); 

%%

% Use same worker name as preop for parity (or swap to your preferred worker)
if ~(exist('record_audio_preop','file')==2)
    clear onCleanupTasks
    error('record_audio_preop() not found on path.');
end
future = parfeval(@record_audio_preop, 1, cfg.AUDIO_FILENAME, workerQueueConstant);
future.Diary;
onCleanupTasks{6} = onCleanup(@() send(workerQueueClient, 'stop'));



% --- No digital I/O / Ripple in DAF ---
%% Verifying connection to ripple system

% initialize xippmex, open connection to neural interface processor (NIP)
digout = 0;
if exist('xippmex','file')==3
    try
        digout = xippmex();
        disp('Using UDP mode') 
        onCleanupTasks{9} = onCleanup(@() xippmex('close'));
    catch err
        warning('xippmex failed %s: %s\n', err.identifier, err.message);
    end
end

if digout
    fprintf('Ripple system found.\n')
    
    %check status of recording
    rippleRec = xippmex('trial');
    
    if isempty(strfind(rippleRec.filebase,cfg.SUBJECT))
        warning('Ripple''s file basename (%s) does NOT contain the subject''s id (%s)',rippleRec.filebase,cfg.SUBJECT);
        str = input('Press enter to continue or ctrl-c to exit\n','s');
    end
    if ~strcmp(rippleRec.status, 'recording') 
        warning('Ripple system connected but NOT recording. DRY RUN.');
        str = input('Press enter to continue or ctrl-c to exit\n','s');
    else
        fprintf('Ripple system recording to file %s%04d\n', rippleRec.filebase, rippleRec.incr_num);
    end
    
else
    fprintf(2,['\n***************************************',...
             '\n** Ripple system NOT found! DRY RUN! **',...
             '\n***************************************\n']);
    str = input('Press enter to continue or ctrl-c to exit\n','s');
end
cfg.DIGOUT = digout;

% % % % % % % % % % % % % % cfg.DIGOUT = 0;

% --- Launch task (same as preop flow) ---
fprintf('Launching task\n');

task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function)
    clear onCleanupTasks
    error('%s should be in current working directory', cfg.TASK_FUNCTION);
end
copyfile(task_function, [cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']);

task_daf_nomidi(cfg);

% --- Cleanup ---
clear onCleanupTasks;
close all;