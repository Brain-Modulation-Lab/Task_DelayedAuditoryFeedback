% Launcher script for DAF     
%%
clear;

AssertOpenGL;
KbName('UnifyKeyNames');
 
% --- Safe local PTB prefs (TEMP for laptop testing) ---
Screen('Preference','SkipSyncTests', 1);         % disable sync for windowed laptop testing
Screen('Preference','VisualDebugLevel', 1);      % fewer splash flashes
Screen('Preference','Verbosity', 3);             % standard logs
PsychDebugWindowConfiguration;                    % opens windowed + alpha layer
 
ListenChar(0);            % do NOT capture keyboard globally
ShowCursor;               % keep cursor visible
Priority(0);              % no realtime priority in local test

%% Parameter settings
% Creating configuration structure
cfg=[];

% subject and session
cfg.SUBJECT = 'test0710' ; %subject identifier
cfg.SESSION_LABEL = 'preop'; %type of session ('test', 'training', 'preop', 'intraop')
cfg.DATA_TYPE = 'task'; %BIDS data type 'beh' for behavioral and task data.

% Task metadata
cfg.TASK = 'daf';
cfg.TASK_VERSION = 1;   
cfg.TASK_FUNCTION = 'Task_DelayedAuditoryFeedback.m';

% cfg parameters
cfg.n_blocks = 1; % Number of blocks
cfg.max_trials = 30; % trial cap
cfg.pause_between_blocks = 0; % Set to true to require keypress between blocks
cfg.audio_frame_size = 128   ; % Number of samples processed per audio frame
cfg.audio_playback_gain = 1 ; % Output gain for delayed signal... might want to run volume calibration for each subject
cfg.fix_cross_dur = 0.; % Duration of fixation cue (seconds)
cfg.delay_dur = 0.; % Pause between fixation and sentence onset (seconds)
cfg.text_stim_dur = 12.0; % Duration for which sentence is displayed and spoken (seconds)
cfg.iti = 2.0; % Inter-trial interval (seconds)
cfg.stim_font_size = 65; 
cfg.stim_max_char_per_line = 38; % wrap text at this length 
cfg.daf_sentences = 'daf_sentences.tsv';
cfg.no_audio_debug_mode = true; % Set to true to skip hardware dependent parts
cfg.LAG_DIAGNOSTICS = true;  

% delayOptions = [0, 100, 150, 200]; % DAF delay condoitions in ms
cfg.delayOptions = 150; % DAF delay conditions in ms (MAX IS 1000ms)
cfg.maxAllowedDelay_ms = 1000;
if any(cfg.delayOptions > cfg.maxAllowedDelay_ms)
    error('One or more delayOptions exceed the maximum allowed delay of %d ms.', cfg.maxAllowedDelay_ms);
end
cfg.catchRatio = 0; % catchRatio = 1/6; % Fraction of catch (no-speak) trials 

%% Paths and configurations
cfg.HOST_AUDIO_API_NAME = 'Windows WASAPI';

% Paths and configurations
if strcmpi(getenv('COMPUTERNAME'),'BML-ALIENWARE')
    cfg.PATH_TASK = 'D:\docs\code\stut_obs\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = 'C:\ieeg_stut'; %source data root folder 
    cfg.AUDIO_DEVICE = 'Speakers/Headphones (Realtek(R) Audio)';
    cfg.HOST_AUDIO_API_NAME = 'Windows WASAPI';
elseif strcmpi(getenv('COMPUTERNAME'),'BML-ALIENWARE2')
    cfg.PATH_TASK = 'D:\docs\code\stut_obs\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = 'C:\ieeg_stut'; %source data root folder 
    cfg.AUDIO_DEVICE = 'Speakers (Realtek(R) Audio)';
    cfg.HOST_AUDIO_API_NAME = 'Windows WASAPI';
elseif ismac
    cfg.PATH_TASK = '/Users/samhansen/Documents/Matlab/Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = '/Users/samhansen/Documents/Matlab/Task_DelayedAuditoryFeedback/stimuli'; %adjust as needed
    cfg.AUDIO_DEVICE_OUT = 'MacBook Pro Speakers';
    cfg.AUDIO_DEVICE_IN  = 'MacBook Pro Microphone';
    cfg.HOST_AUDIO_API_NAME = 'CoreAudio'; 
else
    cfg.PATH_TASK = '~/git/Task_DelayedAuditoryFeedback'; 
    cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata'; %source data root folder 
end

cfg.TEST_SOUND_S = 10; %duration (in seconds) of sound for volume adjustment
cfg.CALIBRATION_BEEPS_N = 5; %number of calibration beeps to play

cfg.AUDIO_AMP = 1;
cfg.GO_BEEP_AMP = 0.5; 
cfg.KEYBOARD_ID = []; % prefered keyboard 

%calibration_beeps(cfg)

%% Initialize external audio recording from USB interface 
if ~cfg.LOCAL_TEST
    if isempty(gcp()), parpool('local',1); end 
    workerQueueConstant = parallel.pool.Constant(@parallel.pool.PollableDataQueue);
    workerQueueClient = fetchOutputs(parfeval(@(x) x.Value, 1, workerQueueConstant));
else
    workerQueueConstant = [];
    workerQueueClient   = [];
end

%% Warnings
warning('on','all'); %enabling warnings
beep off

PsychDefaultSetup(2);

%% Constructing and checking paths and getting next trial run id

%checking data path
pathSub = [cfg.PATH_SOURCEDATA filesep 'sub-' cfg.SUBJECT];
pathSubSes = [pathSub filesep 'ses-' cfg.SESSION_LABEL];
pathSubSesDataType = [pathSubSes filesep cfg.DATA_TYPE];
pathSubSesAudio = [pathSubSes filesep 'audio'];
cfg.PATH_AUDIO = pathSubSesAudio;

if ~isfolder(cfg.PATH_SOURCEDATA)
    error('sourcedata folder %s does not exist',cfg.PATH_SOURCEDATA)
end
if ~isfolder(pathSub)
    fprintf('Creating subject folder %s \n',pathSub)
    mkdir(pathSub)
end
if ~isfolder(pathSubSes)
    fprintf('Creating session folder %s \n',pathSubSes)
    mkdir(pathSubSes)
end
if ~isfolder(pathSubSesDataType)
    fprintf('Creating session folder %s \n',pathSubSesDataType)
    mkdir(pathSubSesDataType)
end
if ~isfolder(pathSubSesAudio)
    fprintf('Creating session folder %s \n',pathSubSesAudio)
    mkdir(pathSubSesAudio)
end

% creating files basename 
fileBaseName = ['sub-' cfg.SUBJECT '_ses-' cfg.SESSION_LABEL '_task-' cfg.TASK '_run-'];

%checking for previous runs based PBT events file
allEventFiles = dir([pathSubSesDataType filesep fileBaseName '*_events.tsv']);
if ~isempty(allEventFiles)
    prevRunIds = regexp({allEventFiles.name}, '_run-(\d+)_' ,'tokens','ignorecase','forceCellOutput','once');
    prevRunIds = cellfun(@(x) str2double(x{1,1}),prevRunIds,'UniformOutput',true);
    runId = max(prevRunIds) + 1;
else
    runId = 1;
end

cfg.RUN_ID = runId;
cfg.PATH_LOG = pathSubSesDataType;
cfg.BASE_NAME = [fileBaseName num2str(cfg.RUN_ID,'%02.f') '_'];
cfg.LOG_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'log.txt'];
cfg.EVENT_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'events.tsv'];
cfg.TRIAL_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'trials.tsv']; % randomized trials info

%% Starting diary
%open diary for this run (saves PTB initialization output)
diary(cfg.LOG_FILENAME);
onCleanupTasks = cell(10,1); 
onCleanupTasks{10} = onCleanup(@() diary('off'));
fprintf('\nConfiuration struture:\n');
disp(cfg)

%% Start audio recording
cfg.AUDIO_FILENAME = [cfg.PATH_AUDIO filesep cfg.BASE_NAME(1:end-1) '.wav'];

% Get the worker to start waiting for messages
filename = cfg.AUDIO_FILENAME; 
% TODO check that @record_audio_preop is on the path
if ~cfg.LOCAL_TEST
    if ~(exist('record_audio_preop','file')==2)
        error('record_audio_preop() not found on path.'); 
    end
    future = parfeval(@record_audio_preop, 1, filename, workerQueueConstant);
    future.Diary;
    onCleanupTasks{6} = onCleanup(@() send(workerQueueClient, 'stop'));
end

%% No ripple system
digout = 0;
cfg.DIGOUT = digout;

%% Launching the task
fprintf('Launching task'); 

% Saving task function in log folder for documentation
task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function)
     clear onCleanupTasks
    error('%s should be in current working directory',cfg.TASK_FUNCTION);
end
copyfile(task_function,[cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']);

Task_DelayedAuditoryFeedback(cfg);

%% Cleaning up
clear onCleanupTasks;
close all;