% Launcher script for Speech Onset Stimulation Task - Nomad version
clear;
figure

% Creating configuration structure
cfg=[];
                                       
% subject and session
cfg.SUBJECT = 'test0715'; %subject identifier
cfg.SESSION_LABEL = 'intraop'; %type of session ('test', 'training', 'preop', 'intraop')
cfg.DATA_TYPE = 'task'; %BIDS data type 'beh' for behavioral and task data. 

cfg.SPEECH_LEVEL_THR=0.025;

% conditions
cfg.STIM_CTRL = 2; % number of times each sentence should be included without stimulation

cfg.STIM_EPOCH = {'go'; 'mid-sentence'};  %name of the stimulation epoch 
cfg.STIM_TRIG = {'go'; 'speech-onset'}; %event that triggers stimulation

cfg.STIM_DELAY = [0; 0.300]; % delay in s from the trigger event to stimulation
cfg.STIM_TL = [2000; 1000]; %train length (ms)

cfg.STIM_FREQ = [30; 130]; %stimulation frequencies in Hz. 

% cfg.STIM_LOC    = {      'ventral'    ;     'dorsal'  }; % name of stimulation locations
% cfg.STIM_ELEC   = {[258 259 260];[261 262 263 ]}; %Id's of the 'ventral'/'dorsal' electrode(s) to be stimulated
% cfg.STIM_AMP    = {     [1 1 1]       ;[1 1 1]}; % amplitude in mA
% cfg.STIM_LABELS = { {'L1a' 'L1b' 'L1c' 'R1a' 'R1b' 'R1c'};{'L2a' 'L2b' 'L2c' 'R2a' 'R2b' 'R2c'}}; %stimulated channel labels

cfg.STIM_LOC    = {      'ventral'    ;     'dorsal'  }; % name of stimulation locations
cfg.STIM_ELEC   = {[2 18 34 6 22 38];[3 19 35 7 23 39]}; %Id's of the 'ventral'/'dorsal' electrode(s) to be stimulated
cfg.STIM_AMP    = {     [1 1 1 1 1 1]       ;[1 1 1 1 1 1] }; % amplitude in mA
cfg.STIM_LABELS = { {'L1a' 'L1b' 'L1c' 'R1a' 'R1b' 'R1c'};{'L2a' 'L2b' 'L2c' 'R2a' 'R2b' 'R2c'}}; %stimulated channel labels

cfg.STIM_LABELS = cellfun(@(x) cellfun(@(y) ['DBS_', y], x, 'UniformOutput', false), cfg.STIM_LABELS, 'UniformOutput', false);

cfg.STIM_PW1 = 66; %duration of first phase is us (will be rounded to closest 33us block)
cfg.STIM_PW_RATIO = 1; %ratio of PW durations of 2nd phase to 1st phase. ratio 10 => second phase is 10 times longer than first phase
cfg.STIM_IPI = 33; %duration of the inter-phase-interval in us
cfg.STIM_FS = nan; %duration of fast settle in ms
cfg.STIM_PL = 0; %polarity (0=cathodic first | 1=annodic first) [20240610AB Note that this is flipped in Ripple's docs]
cfg.STIM_RES = 3; %Scalar value representative of the desired stimulation resolution.
cfg.STIM_RES_mA = 0.05; %1 = 0.010 mA/step, 2 = 0.020 mA/step, 3 = 0.050 mA/step, 4 = 0.100 mA/step, 5 = 0.200 mA/step.
% stimres   step(mA)    max(mA)
% 1         0.01        1.27
% 2         0.02        2.54
% 3         0.05        6.35
% 4         0.1         12.7
% 5         0.2         25.4

cfg.DB_SENTENCES = 'daf_sentence.tsv'; %file name for table with all sentences
%cfg.STIMULATION_COND=1;
cfg.SPEECH_LEVEL_MAD_MULTIPLIER=10; %% The value used to calibrate speech level threshold--x median absolute deviations above the median 
  
% Paths and configurations
cfg.HOST_AUDIO_API_NAME = 'Windows WASAPI';
cfg.SCREEN_RES = [1280 1024]; % Screen resolution

cfg.MIC_API_NAME = 'Windows WASAPI';%MRR

if strcmpi('BML-ALIENWARE',getenv('COMPUTERNAME'))
    cfg.PATH_TASK = 'D:\Task\Task_SentenceOnsetElectricalStimulation';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata'; %source data root folder 
    cfg.AUDIO_DEVICE = 'Speakers (Radial USB Pro)';
    cfg.MIC_DEVICE = 'Analogue 1 + 2 (2- Focusrite USB Audio)';
elseif strcmpi('BML-ALIENWARE2',getenv('COMPUTERNAME'))
    cfg.PATH_TASK = 'D:\Task\Task_SentenceOnsetElectricalStimulation';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata'; %source data root folder 
    cfg.AUDIO_DEVICE = 'Speakers (Radial USB Pro)';
    cfg.MIC_DEVICE = 'Analogue 1 + 2 (2- Focusrite USB Audio)';
else
    cfg.PATH_TASK = '~/git/Task_SentenceOnsetElectricalStimulation'; 
    cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata'; %source data root folder 
end

cfg.TEST_SOUND_S = 10; %duration (in seconds) of sound for volume adjustment
cfg.CALIBRATION_BEEPS_N = 5; %number of calibration beeps to play

cfg.AUDIO_AMP = 1;
cfg.GO_BEEP_AMP = 0.5; 
cfg.KEYBOARD_ID = []; % prefered keyboard 
cfg.SKIP_SYNC_TEST = 1; %should screen test be skipped (use only for debugging)
cfg.CONSERVE_VRAM_MODE = 4096; %kPsychUseBeampositionQueryWorkaround


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
detection_ops.max_dur_seconds = 4; % timeout at 

pa_reqlatencyclass = 1; % set to 1 to not force low latency
pa_freq = []; % use default frequency

% recording parameters
detection_ops.waitscan_seconds = 0.01; % wait this long between recording scans
suggested_latency_seconds = 0.02; % 'suggestedLatency' to input to PsychPortAudio(‘Open’)
n_rec_chans = 1; % number of recording channels
allocated_record_seconds = 10; % 'amountToAllocateSecs' to input to PsychPortAudio(0GetAudioData’)

% PsychPortAudio('Close',[]); % close any devices that were left open
recording_handle = PsychPortAudio('Open', recording_device_index, 2, pa_reqlatencyclass, pa_freq, n_rec_chans, [], suggested_latency_seconds);
PsychPortAudio('GetAudioData', recording_handle, allocated_record_seconds); % initialize recording device with buffer

cfg.PA_RECORDER_FS = PsychPortAudio('GetStatus',recording_handle).SampleRate;

% checking if we are getting audio data from the mic
PsychPortAudio('Start',recording_handle, [], 0);
WaitSecs(0.5);
test_data = PsychPortAudio('GetAudioData', recording_handle);
PsychPortAudio('Stop', recording_handle);
assert(~isempty(test_data));

detection_ops.recording_repeititions = 0; % loop indefinitely until detection
detection_ops.recording_when = 0; % start immediately

cfg.DETECTION_OPS = detection_ops;
cfg.PA_RECORDER_HANDLE = recording_handle;

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
cfg.AUDIO_CALIBRATION_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'audio-calibration.mat'];

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
% TODO check that @record_audio is on the path
if ~(exist('record_audio')==2)
    error('record_audio() function not found. Add it to the MATLAB path.'); 
end
future = parfeval(@record_audio, 1, filename, workerQueueConstant);
future.Diary

onCleanupTasks{6} = onCleanup(@() send(workerQueueClient, 'stop'));

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

%checking that stimulation electrodes are present
if digout
    cfg.RIPPLE_STIM_ELEC = xippmex('elec','stim');
    all_stim_elec = [cfg.STIM_ELEC{:}];
    non_stim_elec_selected = setdiff(all_stim_elec, cfg.RIPPLE_STIM_ELEC);
    if ~isempty(non_stim_elec_selected)
        error('cannot stim through elec %s', num2str(non_stim_elec_selected))
    end

    %setting stimulation resolution for all FEs used
    for i=1:length(all_stim_elec)
        xippmex('stim','res',all_stim_elec(i),cfg.STIM_RES)
    end
    
end

%% Confirmation prompt
cmd = '0';

fprintf('\n===================\n');
fprintf('Task: %s \n',cfg.TASK);
fprintf(2,'Subject: %s\n',cfg.SUBJECT);
fprintf('Session: %s\n',cfg.SESSION_LABEL);
fprintf('Run: %i\n',cfg.RUN_ID);
prompt = sprintf('Command {1=Calibrate mic threshold | 2=Run task | 3=exit} [%s]:\n===================\n',cmd);
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

if strcmp(cmd,'1') % Audio Calibration
    fprintf('Running mic calibration');
    calibrate_soes_detection_threshold(cfg)

elseif strcmp(cmd,'2')
	fprintf('Launching task'); % Launching the task
    
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
end


%% Cleaning up
clear onCleanupTasks;
close all;

