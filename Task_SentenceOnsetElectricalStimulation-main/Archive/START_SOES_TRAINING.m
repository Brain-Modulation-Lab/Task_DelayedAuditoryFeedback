 % Launcher script for Lombar task - Nomad version

% Creating configuration structure
cfg=[];

% subject and session
cfg.SUBJECT = 'test0224';  %subject identifier       
cfg.SESSION_LABEL = 'training'; %type of session ('test', 'training', 'preop', 'intraop')
cfg.DATA_TYPE = 'task'; %BIDS data type 'beh' for behavioral and task data. 
    
cfg.SCREEN_SYNC_RECT = [0 0 1 1]; %rectangle used for screen sync
cfg.SCREEN_SYNC_COLOR = [255 255 255];
  
% Paths and configurations
% MacMini lab
cfg.PATH_TASK = '~/git/Task_Lombard';
cfg.PATH_RAWDATA = '~/Data/DBS/sourcedata'; %rawdata root folder
cfg.AUDIO_DEVICE = 'External Headphones';
cfg.HOST_AUDIO_API_NAME = 'Core Audio';
cfg.SCREEN_ID = 0; % prefered screen 
%cfg.AUDIO_ID = 5;   

cfg.SCALE_FONT = 1.2;

cfg.TEST_SOUND_S = 10; %duration (in seconds) of sound for vlume adjustment
cfg.CALIBRATION_BEEPS_N = 5; %number of calibration beeps to play

cfg.AUDIO_AMP = 1;
cfg.KEYBOARD_ID = []; % prefered keyboard 
cfg.SKIP_SYNC_TEST = 1; %should screen test be skipped (use only for debugging)
cfg.CONSERVE_VRAM_MODE = []; %kPsychUseBeampositionQueryWorkaround

%calibration_beeps(cfg)

%% Task parameters

cfg.TASK = 'lombard'; % name of current task
cfg.TASK_VERSION = 9; % version number for task
cfg.TASK_FUNCTION = 'task_lombard.m';

%% Warngins
warning('on','all'); %enabling warnings
beep off

%% Constructing and checking paths and getting next trial run id

%checking data path
pathSub = [cfg.PATH_RAWDATA filesep 'sub-' cfg.SUBJECT];
pathSubSes = [pathSub filesep 'ses-' cfg.SESSION_LABEL];
pathSubSesDataType = [pathSubSes filesep cfg.DATA_TYPE];
if ~isfolder(cfg.PATH_RAWDATA)
    error('rawdata folder %s does not exist',cfg.PATH_RAWDATA)
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
cfg.TRIAL_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'trials.tsv']; %randomized trials info

%Copying predefined preop setence order
path_preop_trials = [cfg.PATH_TASK filesep 'Stimuli' filesep 'preop_trials.tsv'];
copyfile(path_preop_trials,cfg.TRIAL_FILENAME);

%% Starting diary
%open diary for this run (saves PTB initialization output)
diary(cfg.LOG_FILENAME);
onCleanupTasks = cell(10,1); 
onCleanupTasks{10} = onCleanup(@() diary('off'));
fprintf('\nConfiuration struture:\n');
disp(cfg)

cfg.DIGOUT = 0;

%% Saving task function in log folder for documentation
task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function)
    clear onCleanupTasks
    error('%s.m should be in current working directory',cfg.TASK_FUNCTION);
end
copyfile(task_function,[cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']);

%% Launching the task
task_lombard(cfg);

%% Cleaning up
clear onCleanupTasks

