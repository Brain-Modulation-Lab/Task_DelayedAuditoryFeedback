% Launcher script for Sentence Onset Electrical Stimulation task - Ripple version

%% Creating configuration structure
cfg=[];
cfg.SUBJECT = 'Pilot0224'; %subject identifier
cfg.SENTENCE_SET = 1; %sentence set, always start with 1, if there is time do a run with 2
cfg.N_BLOCKS = 12;
cfg.REST_AFTER_BLOCK = 6;

% cfg.SENTENCE_SET = 2; %sentence set, always start with 1, if there is time do a run with 2
% cfg.N_BLOCKS = 10;
% cfg.REST_AFTER_BLOCK = [];

cfg.SESSION_LABEL = 'intraop'; %type of session ('test', 'training', 'preop', 'intraop')
cfg.DATA_TYPE = 'task'; %BIDS data type 'beh' for behavioral and task data. 

%% Defining path for system
cfg.COMPUTERNAME = getenv('COMPUTERNAME');
if strcmpi('BML-ALIENWARE',cfg.COMPUTERNAME)
    cfg.PATH_TASK = 'D:\Task\Task_P50P3_Sentences';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata'; %source data root folder 
elseif strcmpi('BML-ALIENWARE2',cfg.COMPUTERNAME)
    cfg.PATH_TASK = 'D:\Task\Task_P50P3_Sentences';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata'; %source data root folder 
else
    cfg.PATH_TASK = pwd; 
    cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata'; %source data root folder 
end

% System and Audio configurations
cfg.KEYBOARD_ID = []; % default keyboard 
cfg.AUDIO_DEVICE = []; % [] for default audio device, or system specific option (e.g. 'Speakers (Radial USB Pro)');
cfg.HOST_AUDIO_API_NAME = []; % if AUDIO_DEVICE is specified, HOST_AUDIO_API_NAME is required (e.g. 'Windows WASAPI');
cfg.AUDIO_AMP_CUE = 1; %software controlled volume for cues
cfg.AUDIO_AMP_SENTENCE = 1; %software controlled volume for sentences
cfg.AUDIO_AMP_BEEP = 0.5; %software controlled volume for go beeps

%% Task parameters
cfg.TASK = 'SOES'; % name of current task
cfg.TASK_FUNCTION = 'm_006_speech_onset_detection_and_stimulation_test.m';

% Getting hash for git repo
try
	[s,git_hash_string] = system('git rev-parse HEAD');
catch
    s=-1;
end
if s==0
    cfg.TASK_VERSION = strtrim(git_hash_string); % version number for task
else
	cfg.TASK_VERSION = nan;
end


%% Warngins
warning('on','all'); %enabling warnings
beep off

PsychDefaultSetup(2);

%% Constructing and checking paths and getting next trial run id

%checking data path
pathSub = [cfg.PATH_SOURCEDATA filesep 'sub-' cfg.SUBJECT];
pathSubSes = [pathSub filesep 'ses-' cfg.SESSION_LABEL];
pathSubSesDataType = [pathSubSes filesep cfg.DATA_TYPE];
if ~isfolder(cfg.PATH_SOURCEDATA)
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

%% Starting diary
%open diary for this run (saves PTB initialization output)
diary(cfg.LOG_FILENAME);
onCleanupTasks = cell(10,1); 
onCleanupTasks{10} = onCleanup(@() diary('off'));
fprintf('\nConfiuration struture:\n');
disp(cfg)
fprintf('Computer: %s \n',computer);
fprintf('Architecture: %s \n',computer('arch'));
fprintf('Username: %s \n',char(java.lang.System.getProperty('user.name')))

%% Verifying connection to ripple system

% initialize xippmex, open connection to neural interface processor (NIP)
digout = 0;
if exist('xippmex','file')==3 
    try 
        digout = xippmex('tcp');
        xippmex('addoper',129);
        onCleanupTasks{9} = onCleanup(@() xippmex('close'));  
    catch err
        warning('xippmex failed %s: %s\n', err.identifier, err.message);
    end
end

if digout
    fprintf('Ripple system found.\n')
    
    %ceck status of recording
    rippleRec = xippmex('trial',129);
    
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

%% Saving task function in log folder for documentation
task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function)
    clear onCleanupTasks
    error('%s.m should be in current working directory',cfg.TASK_FUNCTION);
end
copyfile(task_function,[cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']);

%% Launching the task
m_006_speech_onset_detection_and_stimulation_test(cfg);

%% Cleaning up
clear onCleanupTasks

