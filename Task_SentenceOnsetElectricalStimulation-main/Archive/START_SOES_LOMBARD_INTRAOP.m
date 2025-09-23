
% Launcher script for Lombar task - Nomad version

% Creating configuration structure
cfg=[];
                                       
% subject and session
cfg.SUBJECT = 'testAB1213' ; %subject identifier
cfg.SESSION_LABEL = 'intraop'; %type of session ('test', 'training', 'preop', 'intraop')
cfg.DATA_TYPE = 'task'; %BIDS data type 'beh' for behavioral and task data. 

cfg.DB_SENTENCES = 'sentence.csv'; %file name for table with all sentences 

cfg.SCREEN_SYNC_RECT = [0 0 20 20]; %rectangle used for screen sync
cfg.SCREEN_SYNC_COLOR = [255 255 255];
  
% Paths and configurations
% cfg.PATH_TASK = 'D:\Task\Task_Lombard';
% cfg.PATH_RAWDATA = 'D:\DBS\sourcedata'; %rawdata root folder
% cfg.AUDIO_DEVICE = 'Speakers (2- Radial USB Pro)'; % changed becase of the new alienware device string. Before it was 'Speakers (Radial USB Pro)'
cfg.HOST_AUDIO_API_NAME = 'Windows WASAPI';
%cfg.AUDIO_ID = 5; 
cfg.SCREEN_RES = [1280 1024]; % Screen resolution
%cfg.SCREEN_RES = [1920 1080]; % DEV/TESTING only 
cfg.SCALE_FONT = 1;

cfg.MIC_API_NAME = 'Windows WASAPI';%MRR

if strcmpi('BML-ALIENWARE',getenv('COMPUTERNAME'))
    cfg.PATH_TASK = 'D:\Task\Task_SentenceOnsetElectricalStimulation';
    cfg.PATH_RAWDATA = 'D:\DBS\sourcedata'; %source data root folder 
    cfg.AUDIO_DEVICE = 'Speakers (Radial USB Pro)';
    cfg.MIC_DEVICE = 'Jack Mic (Realtek(R) Audio)'; %MRR
    cfg.SCREEN_ID = 3;
elseif strcmpi('BML-ALIENWARE2',getenv('COMPUTERNAME'))
    cfg.PATH_TASK = 'D:\Task\Task_SentenceOnsetElectricalStimulation';
    cfg.PATH_RAWDATA = 'D:\DBS\sourcedata'; %source data root folder 
    cfg.AUDIO_DEVICE = 'Speakers (Radial USB Pro)';
    %cfg.MIC_DEVICE = 'Jack Mic (Realtek(R) Audio)'; %MRR
%     cfg.AUDIO_DEVICE = 'Speakers (Focusrite USB Audio)';
    cfg.MIC_DEVICE = 'Analogue 1 + 2 (2- Focusrite USB Audio)';
    cfg.SCREEN_ID = 2;
else
    cfg.PATH_TASK = '~/git/Task_Lombard'; 
    cfg.PATH_RAWDATA = '~/Data/DBS/sourcedata'; %source data root folder 
end

% cfg.PATH_TASK = '/Users/ao622/git/Task_Lombard';
% cfg.PATH_RAWDATA = '/Users/ao622/Sandbox/rawdata'; %rawdata root folder
% cfg.AUDIO_ID = 2; 
% cfg.SCREEN_ID = 1; % prefered screen 

cfg.TEST_SOUND_S = 10; %duration (in seconds) of sound for volume adjustment
cfg.CALIBRATION_BEEPS_N = 5; %number of calibration beeps to play

cfg.AUDIO_AMP = 1;
cfg.KEYBOARD_ID = []; % prefered keyboard 
cfg.SKIP_SYNC_TEST = 1; %should screen test be skipped (use only for debugging)
cfg.CONSERVE_VRAM_MODE = 4096; %kPsychUseBeampositionQueryWorkaround


%% Task Stimulation parameters
cfg.TASK = 'sent_onset_stim'; % name of current task
cfg.TASK_VERSION = 10; % version number for task
cfg.TASK_FUNCTION = 'task_sent_onset_stim.m';

cfg.STIMULATION_COND=1;
% cfg.STIMULATION_DELAY=dictionary(["go" "speach-onset"  "speach-mid"],[0 0 0.5]);
cfg.SPEECH_LEVEL_THR=0.1;%% calibrated with m_003_speech_onset_level_Distribution (select a value larger than the maxim domain value) 

%calibration_beeps(cfg)

%% Initialize external audio recording from USB interface
% system('powershell -command "./scarlett_audio_testing/launch_audio_server.ps1" &')

% onCleanupTasks{8} = onCleanup(@() system('cmd /c curl -X POST "" http://localhost:8080/stop'));

%  netstat -ano | findstr :8080


% First, create a parallel pool if necessary
if isempty(gcp())
    parpool('local', 1);
end

% Get the worker to construct a data queue on which it can receive messages from the client
workerQueueConstant = parallel.pool.Constant(@parallel.pool.PollableDataQueue);

% Get the worker to send the queue object back to the client
workerQueueClient = fetchOutputs(parfeval(@(x) x.Value, 1, workerQueueConstant));


%% Initialize low-latency microphone

% Initialize the recording devices (MRR)
pa_devices = struct2table(PsychPortAudio('GetDevices'));
pa_devices_sel = contains(pa_devices.HostAudioAPIName,cfg.MIC_API_NAME) & contains(pa_devices.DeviceName,cfg.MIC_DEVICE); 
if sum(pa_devices_sel) == 0 
    disp(pa_devices);
    error('%s - %s not found. Choose one from the list of available microphone devices',cfg.MIC_API_NAME,cfg.MIC_DEVICE);
elseif sum(pa_devices_sel) > 1
    disp(pa_devices);
    error('%s - %s matches more than one device. Choose one from the list of available microphone devices',cfg.MIC_API_NAME,cfg.MIC_DEVICE);
else
    fprintf('The following microphone device was selected');
    disp(pa_devices(pa_devices_sel,:));
    cfg.MIC_ID = pa_devices.DeviceIndex(pa_devices_sel);
end
recording_device_index = cfg.MIC_ID; 
detection_ops.loudness_threshold = cfg.SPEECH_LEVEL_THR; % range 0 to 1
detection_ops.max_dur_seconds = inf; % don't timeout the detection function
pa_reqlatencyclass = 1; % set to 1 to not force low latency
pa_freq = []; % use default frequency
% recording parameters
detection_ops.waitscan_seconds = 0.01; % wait this long between recording scans
suggested_latency_seconds = 0.02; % 'suggestedLatency' to input to PsychPortAudio(‘Open’)
n_rec_chans = 1; % number of recording channels
allocated_record_seconds = 1; % 'amountToAllocateSecs' to input to PsychPortAudio(‘GetAudioData’)
% PsychPortAudio('Close',[]); % close any devices that were left open
recording_handle = PsychPortAudio('Open', recording_device_index, ...
        2, pa_reqlatencyclass, pa_freq, n_rec_chans, [], ...
        suggested_latency_seconds);
PsychPortAudio('GetAudioData', recording_handle, ...
        allocated_record_seconds); % initialize recording device with buffer
% start recording
detection_ops.recording_repeititions = 0; % loop indefinitely until detection
detection_ops.recording_when = 0; % start immediately
cfg.DetectionOPS=detection_ops;
cfg.RecorderHandle=recording_handle;


%% Build table specifying condition for each trials 
% conditions = sentences x stim_epoch x stim_freq x stim_loc


% SENTENCES
fac_sentences = readtable([cfg.PATH_TASK filesep 'Stimuli' filesep cfg.DB_SENTENCES],'Delimiter',',','FileType','text');    
fac_sentences = fac_sentences(1:8, :);
fac_sentences.idx = (1:height(fac_sentences))';


% STIM EPOCH
epoch = {'go'; 'speech-onset'; 'speech-mid'};
delay = [0; 0; 0.5];
idx = (1:length(epoch))';
fac_stim_epoch_tbl = table(idx, epoch, delay, 'VariableNames', {'idx', 'stim_epoch', 'stim_delay'}); 

% STIM FREQUENCY
freq = [50; 130];
idx = (1:length(freq))';
fac_stim_freq_tbl = table(idx, freq, 'VariableNames', {'idx', 'stim_freq'});

% STIM LOCATION
loc = {'ventral'; 'dorsal'};
idx = (1:length(loc))';
fac_stim_loc_tbl = table(idx, loc, 'VariableNames', {'idx', 'stim_loc'});




factors_tbls = {fac_sentences, fac_stim_epoch_tbl, fac_stim_freq_tbl, fac_stim_loc_tbl};

lens = cellfun(@(x) x.idx, factors_tbls, 'UniformOutput', false);
[a, b, c, d] = ndgrid(lens{:});
all_trials_tbl = table(a(:), b(:), c(:), d(:)); 

% combine factors idxs with information from factor tables
for ifac = 1:length(factors_tbls)
    all_trials_tbl.idx = all_trials_tbl{:, ifac}; 
    all_trials_tbl = join(all_trials_tbl, factors_tbls{ifac}, 'keys', 'idx');
end

% randomize trials
all_trials_tbl = all_trials_tbl(randperm(height(all_trials_tbl)), :);

% polish table 
dbTrials = all_trials_tbl(:, 6:end); 
dbTrials.trial_id = (1:height(dbTrials))';
dbTrials = movevars(dbTrials, 'trial_id', 'Before', 1); % move to leftmost column


%% Warnings
warning('on','all'); %enabling warnings
beep off

PsychDefaultSetup(2);
% Checking screen
screenRes = Screen('Resolution',cfg.SCREEN_ID);
if ~isempty(cfg.SCREEN_RES)
    if cfg.SCREEN_RES(2)~= screenRes.height || cfg.SCREEN_RES(1) ~= screenRes.width
        disp(screenRes)
        error('Screen resolution does not match specified value cfg.SCREEN_RES = [%i, %i]',cfg.SCREEN_RES(1),cfg.SCREEN_RES(2));
    end
end


%% Constructing and checking paths and getting next trial run id

%checking data path
pathSub = [cfg.PATH_RAWDATA filesep 'sub-' cfg.SUBJECT];
pathSubSes = [pathSub filesep 'ses-' cfg.SESSION_LABEL];
pathSubSesDataType = [pathSubSes filesep cfg.DATA_TYPE];
pathSubSesAudio = [pathSubSes filesep 'audio'];
cfg.PATH_AUDIO = pathSubSesAudio;


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

writetable(dbTrials,cfg.TRIAL_FILENAME,'Delimiter','\t','FileType','text');

%% Start audio recording
% %  system('powershell -command "./scarlett_audio_testing/launch_audio_server.ps1" &')
% 
% system_cmd = ['cmd /c curl -X POST -H "Content-Type: text/plain" --data "" http://localhost:8080/start?save_to="' cfg.AUDIO_FILENAME '"'];
% system_cmd = ['cmd /c curl -X POST --data "{}" http://localhost:8080/?op=start&save_to="' cfg.AUDIO_FILENAME '"'];
% % system_cmd = ['cmd /c curl -X PUT -d save_to="' cfg.AUDIO_FILENAME '"'  ' http://localhost:8080/start'];
% system(system_cmd);
% % curl -X PUT -d argument=value -d argument2=value2 http://localhost:8080
% 
%         
% % onCleanupTasks{9} = onCleanup(@() system('cmd /c curl -X POST "" http://localhost:8080/stop)
% % cmd /c curl -X POST "" http://localhost:8080/stop
% system('cmd /c curl -X POST "" http://localhost:8080/stop');

% ---- MATLAB-only option -------
cfg.AUDIO_FILENAME = [cfg.PATH_AUDIO filesep cfg.BASE_NAME(1:end-1) '.wav'];

% Get the worker to start waiting for messages
filename = cfg.AUDIO_FILENAME;
future = parfeval(@record_audio, 1, filename, workerQueueConstant);
future.Diary


%% Starting diary
%open diary for this run (saves PTB initialization output)
diary(cfg.LOG_FILENAME);
onCleanupTasks = cell(10,1); 
onCleanupTasks{10} = onCleanup(@() diary('off'));
fprintf('\nConfiuration struture:\n');
disp(cfg)

%% Verifying connection to ripple system

% initialize xippmex, open connection to neural interface processor (NIP)
digout = 0;
if exist('xippmex','file')==3
    try
        switch cfg.protocol
            case 'tcp'
                try     n  q
                    digout = xippmex('tcp');
                    xippmex('addoper',129);
                    disp('Using TCP mode')
                catch
                    digout = xippmex();
                    disp('Using UDP mode')
                    warning('Inconsistent network protocol!')
                end
            case 'udp'
                try
                    digout = xippmex();
                    disp('Using UDP mode')

                catch
                    digout = xippmex('tcp');
                    xippmex('addoper',129);
                    disp('Using TCP mode')
                    warning('Inconsistent network protocol!')
                end
        end
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
task_sent_onset_stim(cfg);

%% Stop audio
% % for the python-flask version
% system('cmd /c curl -X POST "" http://localhost:8080/stop')

% in the matlab-only version 
send(workerQueueClient, 'stop');

%% Cleaning up
clear onCleanupTasks

