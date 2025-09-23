   % Launcher script for Speech Onset Stimulation Task - Nomad version
clear;

% Creating configuration structure
cfg=[];
                                       
% subject and session
cfg.SUBJECT = 'test0710' ; %subject identifier
cfg.SESSION_LABEL = 'preop'; %type of session ('test', 'training', 'preop', 'intraop')
cfg.DATA_TYPE = 'task'; %BIDS data type 'beh' for behavioral and task data. 

% conditions
cfg.STIM_CTRL = 2; % number of times each sentence should be included without stimulation

cfg.DB_SENTENCES = 'sentence.csv'; %file name for table with all sentences
  
% Paths and configurations
cfg.HOST_AUDIO_API_NAME = 'Windows WASAPI';

% Paths and configurations
if strcmpi('BML-ALIENWARE',getenv('COMPUTERNAME'))
    cfg.PATH_TASK = 'D:\Task\Task_SentenceOnsetElectricalStimulation';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata'; %source data root folder 
    cfg.AUDIO_DEVICE = 'Speakers/Headphones (Realtek(R) Audio)';
    cfg.HOST_AUDIO_API_NAME = 'Windows WASAPI';
elseif strcmpi('BML-ALIENWARE2',getenv('COMPUTERNAME'))
    cfg.PATH_TASK = 'D:\Task\Task_SentenceOnsetElectricalStimulation';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata'; %source data root folder 
    cfg.AUDIO_DEVICE = 'Speakers (Realtek(R) Audio)';
    cfg.HOST_AUDIO_API_NAME = 'Windows WASAPI';
else
    cfg.PATH_TASK = '~/git/Task_SentenceOnsetElectricalStimulation'; 
    cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata'; %source data root folder 
end

cfg.TEST_SOUND_S = 10; %duration (in seconds) of sound for volume adjustment
cfg.CALIBRATION_BEEPS_N = 5; %number of calibration beeps to play

cfg.AUDIO_AMP = 1;
cfg.GO_BEEP_AMP = 0.5; 
cfg.KEYBOARD_ID = []; % prefered keyboard 

% Task Stimulation parameters
cfg.TASK = 'sent_onset_stim'; % name of current task
cfg.TASK_VERSION = 2; % version number for task
cfg.TASK_FUNCTION = 'task_sent_onset_stim.m';

%calibration_beeps(cfg)
%% Initialize external audio recording from USB interface 
if isempty(gcp())
    parpool('local', 1);
    wait(); 
end

% Get the worker to construct a data queue on which it can receive messages from the client
workerQueueConstant = parallel.pool.Constant(@parallel.pool.PollableDataQueue);

% Get the worker to send the queue object back to the client
workerQueueClient = fetchOutputs(parfeval(@(x) x.Value, 1, workerQueueConstant));

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

%% creating trials table
dbTrials = create_trials_table(cfg);
cfg.TRIAL_TABLE = dbTrials;

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
if ~(exist('record_audio_preop')==2)
    error('record_audio_preop() function not found. Add it to the MATLAB path.'); 
end
future = parfeval(@record_audio_preop, 1, filename, workerQueueConstant);
future.Diary

onCleanupTasks{6} = onCleanup(@() send(workerQueueClient, 'stop'));

%% No ripple system
digout = 0;
cfg.DIGOUT = digout;

%% Launching the task
fprintf('Launching task'); 

%saving trials table
writetable(dbTrials,cfg.TRIAL_FILENAME,'Delimiter','\t','FileType','text');

% Saving task function in log folder for documentation
task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function)
    clear onCleanupTasks
    error('%s.m should be in current working directory',cfg.TASK_FUNCTION);
end
copyfile(task_function,[cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']);

task_sent_onset_stim(cfg);

%% Cleaning up
clear onCleanupTasks;
close all;

