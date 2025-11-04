function start_daf_intraop_master_TCP
% START_DAF_INTRAOP_MASTER (TCP) — launcher for the DAF task (master side)

%% Setup experiment configuration
cfg = struct();
cfg.SESSION_LABEL = 'intraop';
cfg.SUBJECT       = 'daftestsub';
cfg.DATA_TYPE     = 'task';
cfg.RECORD_AUDIO  = false;
cfg.LagMetrics    = false;
cfg.PTB           = false;

cfg.TASK          = 'daf';
cfg.TASK_VERSION  = 1;
cfg.TASK_FUNCTION = 'task_daf_master_TCP.m';

% === TCP ENGINE CONNECTION ===
cfg.ENGINE_HOST       = '192.168.0.185';   % <-- set to engine (Windows) IP
cfg.ENGINE_PORT       = 4444;         % TCP port engine listens on
cfg.NET_ACK_TIMEOUT_S = 0.10;         % "ACK" wait timeout for PING/SYNCBEEP, etc.
cfg.NET_MAX_RETRIES   = 2;            % retries when waiting for ACK

% Core DAF parameters
cfg.max_trials             = inf;
cfg.audio_sample_rate      = 48000;
cfg.audio_frame_size       = 60;
cfg.audio_playback_gain    = 1;
cfg.fix_cross_dur          = 0.0;
cfg.text_stim_dur          = 10;
cfg.stim_font_size         = 50;
cfg.stim_max_char_per_line = 30;
cfg.catchRatio             = 0;
cfg.max_stim_repeats       = 2;
cfg.max_delay_repeats      = 4;
cfg.same_trials_across_blocks = true;
cfg.maxAllowedDelay_ms = 1000;
cfg.daf_stim_file = ['daf_sentences_' cfg.SESSION_LABEL '.tsv'];

switch cfg.SESSION_LABEL
    case 'preop'
        cfg.delay_values_ms = [0 100 150 200 250];
        cfg.n_blocks = 2;
    case 'intraop'
        cfg.delay_values_ms = [0 100];
        cfg.n_blocks = 4;
    otherwise
        error('Unknown session label: %s', cfg.SESSION_LABEL);
end
if any(cfg.delay_values_ms > cfg.maxAllowedDelay_ms)
    error('One or more delay options exceed max %d ms.', cfg.maxAllowedDelay_ms);
end

%% PTB optional setup (same as before)
usePTB = false;
if isfield(cfg,'PTB')
    if islogical(cfg.PTB), usePTB = cfg.PTB;
    elseif ischar(cfg.PTB) || isstring(cfg.PTB)
        usePTB = any(strcmpi(string(cfg.PTB), ["true","on","ptb","1"]));
    end
end
fprintf('[Starter] PTB backend requested: %d\n', usePTB);
if usePTB && exist('Screen','file')>0
    warning('on','all'); beep off; PsychDefaultSetup(2);
    Screen('Preference','SkipSyncTests',1);
    Screen('Preference','ConserveVRAM',4096);
    Screen('Preference','VisualDebugLevel',1);
    Screen('Preference','Verbosity',3);
    PsychDebugWindowConfiguration;
end

%% Parallel pool for optional audio recording
workerQueue = [];
workerQueueConstant = [];

if isfield(cfg,'RECORD_AUDIO') && cfg.RECORD_AUDIO
    hasPCT = (exist('parpool','file') == 2) && license('test','Distrib_Computing_Toolbox');
    if ~hasPCT
        warning('Parallel Computing Toolbox not available. Disabling RECORD_AUDIO.');
        cfg.RECORD_AUDIO = false;
    else
        if isempty(gcp('nocreate'))
            parpool('local', 1);
        end
        workerQueue = parallel.pool.PollableDataQueue;
        workerQueueConstant = parallel.pool.Constant(workerQueue);
    end
end

%% Paths (unchanged)
if strcmpi(getenv('COMPUTERNAME'), 'BML-ALIENWARE2')
    cfg.PATH_TASK       = 'D:\Task\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata';
elseif ismac
    cfg.PATH_TASK       = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/scripts';
    cfg.PATH_SOURCEDATA = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/stimuli';
else
    cfg.PATH_TASK       = '~/git/Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata';
end

% Build dirs
pathSub = fullfile(cfg.PATH_SOURCEDATA, ['sub-' cfg.SUBJECT]);
pathSubSes = fullfile(pathSub, ['ses-' cfg.SESSION_LABEL]);
pathSubSesDataType = fullfile(pathSubSes, cfg.DATA_TYPE);
pathSubSesAudio = fullfile(pathSubSes, 'audio');
for p = {cfg.PATH_SOURCEDATA, pathSub, pathSubSes, pathSubSesDataType, pathSubSesAudio}
    if ~isfolder(p{1}), mkdir(p{1}); end
end
cfg.PATH_AUDIO = pathSubSesAudio;

%% Filenames
fileBaseName  = ['sub-' cfg.SUBJECT '_ses-' cfg.SESSION_LABEL '_task-' cfg.TASK '_run-'];
allEventFiles = dir(fullfile(pathSubSesDataType, [fileBaseName '*_events.tsv']));
if ~isempty(allEventFiles)
    prevRunIds = regexp({allEventFiles.name}, '_run-(\d+)_', 'tokens','ignorecase');
    prevRunIds = cellfun(@(x) str2double(x{1,1}), prevRunIds);
    runId = max(prevRunIds) + 1;
else
    runId = 1;
end
cfg.RUN_ID = runId;
cfg.PATH_LOG = pathSubSesDataType;
cfg.BASE_NAME = [fileBaseName, sprintf('%02d_', runId)];
cfg.LOG_FILENAME    = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'log.txt']);
cfg.EVENT_FILENAME  = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'events.tsv']);
cfg.TRIAL_FILENAME  = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'trials.tsv']);
cfg.AUDIO_FILENAME  = fullfile(cfg.PATH_AUDIO, [cfg.BASE_NAME(1:end-1) '.wav']);

%% Start diary
diary(cfg.LOG_FILENAME);
oc = onCleanup(@() diary('off'));
disp(cfg);

%% Scripts folder
%cd('./scripts');

%% Optional audio recording
if cfg.RECORD_AUDIO
    if ~(exist('record_audio','file')==2), error('record_audio() not found'); end
    future = parfeval(@record_audio, 1, cfg.AUDIO_FILENAME, workerQueueConstant);
    future.Diary;
    recCleanup = onCleanup(@() send(workerQueue, 'stop')); %#ok<NASGU>
end

%% Ripple (unchanged)
cfg.DIGOUT = 0;
if exist('xippmex','file')==3
    try
        digout = xippmex();  %#ok<NASGU>
        cfg.DIGOUT = 1; onCleanup(@() xippmex('close'));
    catch err
        warning('xippmex init failed: %s', err);
    end
end

%% === OPEN TCP CLIENT TO ENGINE ===
try
    c = connectEngineWithRetry(cfg.ENGINE_HOST, cfg.ENGINE_PORT, 10, 3); % 10 tries, 3s timeout
    cfg.DAF_TCP = c;
    cfg.NET_RXBUF = uint8([]);  % receive buffer for line parsing
    fprintf("DAF TCP connected to %s:%d\n", cfg.ENGINE_HOST, cfg.ENGINE_PORT);
catch ME
    warning('Could not open TCP to engine: %s', message);
    cfg.DAF_TCP = [];
end
tcpCleanup = onCleanup(@() tryCloseTcp(cfg));

%% Launch task
fprintf('Launching task\n');
task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function), error('%s not found in current folder', cfg.TASK_FUNCTION); end
copyfile(task_function, [cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']);
feval(strrep(cfg.TASK_FUNCTION,'.m',''), cfg);

close all;
end

function tryCloseTcp(cfg)
try
    if isfield(cfg,'DAF_TCP') && ~isempty(cfg.DAF_TCP)
        clear cfg; % tcpclient cleans when handle cleared
    end
catch
end
end

function c = connectEngineWithRetry(host, port, attempts, timeout)
    lastErr = [];
    for k = 1:attempts
        try
            c = tcpclient(host, port, 'Timeout', timeout);
            fprintf('[Master] Connected to %s:%d on attempt %d\n', host, port, k);
            return
        catch ME
            lastErr = ME;
            fprintf('[Master] Connect attempt %d failed: %s\n', k, ME.message);
            pause(0.5);
        end
    end
    error('Failed to connect to engine after %d attempts: %s', attempts, lastErr.message);
end

