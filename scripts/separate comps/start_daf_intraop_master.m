function start_daf_intraop_master
% Intraop Launcher for DAF (MASTER TASK COMPUTER)
% - Sets up subject/session, paths, logs
% - Opens USB-serial link to DAF engine box
% - (Optionally) checks Ripple
% - Launches your task script (unchanged) with cfg passed in

figure;

% --- Centralized configuration structure ---
cfg = struct();

cfg.SESSION_LABEL = 'intraop';   % or 'preop'
cfg.SUBJECT       = 'daftestsub';
cfg.DATA_TYPE     = 'task';
cfg.RECORD_AUDIO  = 1;

% Task metadata (keep your existing Task_* script name here)
cfg.TASK          = 'daf';
cfg.TASK_VERSION  = 1;
cfg.TASK_FUNCTION = 'task_daf.m';  % your existing task script

% --- DAF control transport (USB-serial to DAF computer) ---
cfg.DAF_CONTROL        = 'usb';
cfg.USB_PORT_MASTER    = "COM7";     % <-- set to MASTER's port connected to DAF box
cfg.USB_BAUDRATE       = 115200;
cfg.DAF_ACK_TIMEOUT_S  = 0.100;      % used later by sender helpers
cfg.DAF_MAX_RETRIES    = 2;
cfg.DAF_START_OFFSET_S = 0.000;      % if you want START relative to visual onset

% --- Core DAF parameters kept for parity/logging (audio runs on DAF box) ---
cfg.max_trials             = inf;
cfg.audio_sample_rate      = 44100;
cfg.audio_frame_size       = 60;
cfg.audio_playback_gain    = 0.1;
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
end
if any(cfg.delay_values_ms > cfg.maxAllowedDelay_ms)
    error('One or more delay options exceed max %d ms.', cfg.maxAllowedDelay_ms);
end

% --- Psychtoolbox / visual prefs (master shows visuals) ---
cfg.SKIP_SYNC_TEST     = 1;
cfg.CONSERVE_VRAM_MODE = 4096;
cfg.LOCAL_TEST         = 0;

warning('on','all'); beep off;
PsychDefaultSetup(2);
Screen('Preference','SkipSyncTests', cfg.SKIP_SYNC_TEST);
Screen('Preference','ConserveVRAM', cfg.CONSERVE_VRAM_MODE);
Screen('Preference','VisualDebugLevel', 1);
Screen('Preference','Verbosity', 3);
PsychDebugWindowConfiguration;   % windowed bench testing
close all force; Screen('CloseAll');

% --- Parallel pool for optional audio recording (MASTER-side) ---
if isempty(gcp('nocreate')), parpool('local',1); end
workerQueueConstant = parallel.pool.Constant(@parallel.pool.PollableDataQueue);
workerQueueClient   = fetchOutputs(parfeval(@(x) x.Value, 1, workerQueueConstant));

% --- Paths & output folders ---
if strcmpi(getenv('COMPUTERNAME'), 'BML-ALIENWARE2')
    cfg.PATH_TASK       = 'D:\Task\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata';
elseif ismac
    cfg.PATH_TASK       = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/';
    cfg.PATH_SOURCEDATA = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/stimuli';
else
    cfg.PATH_TASK       = '~/git/Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata';
end

pathSub            = fullfile(cfg.PATH_SOURCEDATA, ['sub-' cfg.SUBJECT]);
pathSubSes         = fullfile(pathSub, ['ses-' cfg.SESSION_LABEL]);
pathSubSesDataType = fullfile(pathSubSes, cfg.DATA_TYPE);
pathSubSesAudio    = fullfile(pathSubSes, 'audio');
for p = {cfg.PATH_SOURCEDATA, pathSub, pathSubSes, pathSubSesDataType, pathSubSesAudio}
    if ~isfolder(p{1}), mkdir(p{1}); end
end
cfg.PATH_AUDIO = pathSubSesAudio;

% --- Run basename / filenames ---
fileBaseName  = ['sub-' cfg.SUBJECT '_ses-' cfg.SESSION_LABEL '_task-' cfg.TASK '_run-'];
allEventFiles = dir(fullfile(pathSubSesDataType, [fileBaseName '*_events.tsv']));
if ~isempty(allEventFiles)
    prevRunIds = regexp({allEventFiles.name}, '_run-(\d+)_', 'tokens', 'ignorecase');
    prevRunIds = cellfun(@(x) str2double(x{1,1}), prevRunIds, 'UniformOutput', true);
    runId = max(prevRunIds) + 1;
else
    runId = 1;
end
cfg.RUN_ID         = runId;
cfg.PATH_LOG       = pathSubSesDataType;
cfg.BASE_NAME      = [fileBaseName, sprintf('%02d_', runId)];
cfg.LOG_FILENAME   = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'log.txt']);
cfg.EVENT_FILENAME = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'events.tsv']);
cfg.TRIAL_FILENAME = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'trials.tsv']);
cfg.AUDIO_FILENAME = fullfile(cfg.PATH_AUDIO, [cfg.BASE_NAME(1:end-1) '.wav']);

% --- Start diary ---
diary(cfg.LOG_FILENAME);
oc = onCleanup(@() diary('off'));
disp(cfg);

% --- Change to scripts folder (your task expects this) ---
cd('./scripts');

% --- Start MASTER-side audio recording (optional; ensure device doesn't conflict with DAF box) ---
if cfg.RECORD_AUDIO
    if ~(exist('record_audio','file')==2)
        error('record_audio() not found on path.');
    end
    future = parfeval(@record_audio, 1, cfg.AUDIO_FILENAME, workerQueueConstant);
    future.Diary;
    recCleanup = onCleanup(@() send(workerQueueClient, 'stop')); %#ok<NASGU>
end

% --- (Optional) Ripple check: leave as-is if you use it; otherwise skip ---
cfg.DIGOUT = 0;
if exist('xippmex','file')==3
    try
        digout = xippmex();  % UDP default; adjust if you use TCP
        cfg.DIGOUT = digout~=0;
        onCleanup(@() xippmex('close'));
    catch err
        warning('xippmex init failed: %s', err);
    end
end

% --- Open USB-serial to DAF box; pass handle in cfg ---
try
    s = serialport(cfg.USB_PORT_MASTER, cfg.USB_BAUDRATE);
    configureTerminator(s,"LF");
    cfg.DAF_SERIAL = s;                 % pass handle to task
    disp("DAF USB connected on " + cfg.USB_PORT_MASTER);
    % quick health check (optional): send PING, expect ACK in the task's sender helper
catch ME
    warning('Could not open DAF USB port: %s', ME);
    cfg.DAF_SERIAL = [];
end
sCleanup = onCleanup(@() tryCloseSerial(cfg));

% --- Launch task (unchanged) ---
fprintf('Launching task\n');
task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function)
    error('%s not found in current folder', cfg.TASK_FUNCTION);
end
copyfile(task_function, [cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']);
feval(strrep(cfg.TASK_FUNCTION,'.m',''), cfg);   % call your task function by name

% --- Done ---
close all;

end  % function

function tryCloseSerial(cfg)
    try
        if isfield(cfg,'DAF_SERIAL') && ~isempty(cfg.DAF_SERIAL) && isvalid(cfg.DAF_SERIAL)
            clear cfg.DAF_SERIAL;  % clears the serialport handle explicitly
        end
    catch
        % ignore errors
    end
end