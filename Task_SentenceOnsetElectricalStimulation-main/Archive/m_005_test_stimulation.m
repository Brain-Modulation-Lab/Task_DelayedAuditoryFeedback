 % Launcher script for Set Ripple - Nomad version

% Creating configuration structure
cfg=[];

% subject and session
cfg.SUBJECT = 'test0330'; %subject identifier
cfg.SESSION_LABEL = 'intraop'; %type of session ('test', 'training', 'preop', 'intraop')

% Paths and configurations
cfg.PATH_TASK = 'D:\Task\Task_SetRipple';
cfg.PATH_RAWDATA = 'D:\DBS\sourcedata'; %rawdata root folder
cfg.TASK = 'SetRipple';
cfg.KEYBOARD_ID = []; % prefered keyboard 

%% Warngins
warning('on','all'); %enabling warnings
beep off

%% Constructing and checking paths and getting next trial run id

%checking data path
pathSub = [cfg.PATH_RAWDATA filesep 'sub-' cfg.SUBJECT];
pathSubSes = [pathSub filesep 'ses-' cfg.SESSION_LABEL];
pathSubSesTask = [pathSubSes filesep 'task'];
pathSubSesRipple = [pathSubSes filesep 'ripple'];
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
if ~isfolder(pathSubSesTask)
    fprintf('Creating session folder %s \n',pathSubSesTask)
    mkdir(pathSubSesTask)
end
if ~isfolder(pathSubSesRipple)
    fprintf('Creating session folder %s \n',pathSubSesRipple)
    mkdir(pathSubSesRipple)
end

% creating files basename 
fileBaseName = ['sub-' cfg.SUBJECT '_ses-' cfg.SESSION_LABEL '_task-' cfg.TASK '_run-'];

%checking for previous runs based PBT Log file
allEventFiles = dir([pathSubSesTask filesep fileBaseName '*_log.txt']);
if ~isempty(allEventFiles)
    prevRunIds = regexp({allEventFiles.name}, '_run-(\d+)_' ,'tokens','ignorecase','forceCellOutput','once');
    prevRunIds = cellfun(@(x) str2double(x{1,1}),prevRunIds,'UniformOutput',true);
    runId = max(prevRunIds) + 1;
else
    runId = 1;
end

cfg.RUN_ID = runId;
cfg.PATH_LOG = pathSubSesTask;
cfg.BASE_NAME = [fileBaseName num2str(cfg.RUN_ID,'%02.f') '_'];
cfg.LOG_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'log.txt'];
cfg.PATH_RIPPLE = pathSubSesRipple;

%% Starting diary
%open diary for this run (saves PTB initialization output)
diary(cfg.LOG_FILENAME);
onCleanupTasks = cell(10,1); 
onCleanupTasks{10} = onCleanup(@() diary('off'));
fprintf('\nConfiguration struture:\n');
disp(cfg)

%% Confirmation prompt
cmd = '0';

fprintf('\n===================\n');
fprintf('Task: %s \n',cfg.TASK);
fprintf(2,'Subject: %s\n',cfg.SUBJECT);
fprintf('Session: %s\n',cfg.SESSION_LABEL);
fprintf('Run: %i\n',cfg.RUN_ID);
prompt = sprintf('Command {1=Simple example | 2=TBD | 3=exit} [%s]:\n===================\n',cmd);
answer = input(prompt,'s');

if isempty(answer)
    answer = cmd;
else
    answer = strtrim(answer);
end
if ~ismember(answer,{'1','2','3'})
    clear onCleanupTasks
    error('Task canceled by user')
else
    cmd = answer;
end

if strcmp(cmd,'1')
    fprintf('Test Stimulation');
   
    task_stimulate_example()
end


%% Cleaning up
clear onCleanupTasks

