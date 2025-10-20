% Intraop Launcher for DAF (non-PTB)
figure;

% --- Centralized configuration structure ---
cfg = [];

% Subject/session metadata
cfg.SUBJECT       = 'test0715';
cfg.SESSION_LABEL = 'intraop';
cfg.DATA_TYPE     = 'task';

% Task metadata (non-PTB task entry point)
cfg.TASK          = 'daf';
cfg.TASK_VERSION  = 1;
cfg.TASK_FUNCTION = 'task_daf.m';
cfg.daf_stim_file = 'daf_sentences.tsv'; % Stim text file

% Core DAF parameters
cfg.n_blocks                 = 1;     % number of blocks
cfg.max_trials               = 30;    % optional cap
cfg.pause_between_blocks     = 0;     % unused by task_daf_nonptb (parity w/ preop)
cfg.audio_sample_rate        = 44100; % Hz
cfg.audio_frame_size         = 128;   % samples per frame
cfg.audio_playback_gain      = 0.1;   % DAF output gain
cfg.fix_cross_dur            = 0.0;   % seconds
cfg.delay_dur                = 0.0;   % seconds
cfg.text_stim_dur            = 12.0;  % seconds
cfg.iti                      = 2.0;   % symmetry with preop (not used directly)
cfg.stim_font_size           = 5;
cfg.stim_max_char_per_line   = 38;
cfg.catchRatio               = 0;
cfg.max_stim_repeats         = 2;
cfg.max_delay_repeats        = 4;
cfg.same_trials_across_blocks= true;

% DAF delay conditions (ms)
cfg.delay_values_ms       = [0 150];
cfg.maxAllowedDelay_ms    = 1000;
if any(cfg.delay_values_ms > cfg.maxAllowedDelay_ms)
    error('One or more delayOptions exceed the maximum allowed delay of %d ms.', cfg.maxAllowedDelay_ms);
end

% Diagnostics / flags
cfg.no_audio_debug_mode   = true;
cfg.LAG_DIAGNOSTICS       = true;

% Choose LOCAL_TEST mode explicitly
cfg.LOCAL_TEST            = 0;

% Paths and device configuration
if strcmpi(getenv('COMPUTERNAME'), 'BML-ALIENWARE2') %% intraop rig laptop
    cfg.PATH_TASK        = 'D:\Task\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA  = 'D:\DBS\sourcedata';
    cfg.AUDIO_DEVICE_OUT = 'Speakers (Radial USB Pro)';
elseif ismac
    cfg.PATH_TASK        = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/';
    cfg.PATH_SOURCEDATA  = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/stimuli';
    cfg.AUDIO_DEVICE_OUT = 'MacBook Pro Speakers';
    cfg.AUDIO_DEVICE_IN  = 'MacBook Pro Microphone';
elseif strcmpi(getenv('COMPUTERNAME'), '677-GUE-WL-0010') % Andrew Meier work laptop
    cfg.PATH_TASK        = 'C:\docs\code\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA  = 'C:\ieeg_stut';
    cfg.AUDIO_DEVICE_IN  = 'Microphone Array (Intel® Smart Sound Technology for Digital Microphones)';
    cfg.AUDIO_DEVICE_OUT = 'Speakers (HIFI Audio)';
else
    cfg.PATH_TASK        = '~/git/Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA  = '~/Data/DBS/sourcedata';
end

% Misc parity with preop
cfg.TEST_SOUND_S        = 10;
cfg.CALIBRATION_BEEPS_N = 5;
cfg.AUDIO_AMP           = 1;
cfg.GO_BEEP_AMP         = 0.5;
cfg.KEYBOARD_ID         = [];

% --- Non-PTB warnings/setup ---
warning('on','all'); beep off;

% Close any open figures (PTB close calls removed)
close all force;

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

cfg.RUN_ID         = runId;
cfg.PATH_LOG       = pathSubSesDataType;
cfg.BASE_NAME      = [fileBaseName, sprintf('%02d_', runId)];
cfg.LOG_FILENAME   = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'log.txt']);
cfg.EVENT_FILENAME = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'events.tsv']);
cfg.TRIAL_FILENAME = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'trials.tsv']);
cfg.AUDIO_FILENAME = fullfile(cfg.PATH_AUDIO, [cfg.BASE_NAME(1:end-1) '.wav']);

% --- Start diary ---
diary(cfg.LOG_FILENAME);
onCleanupTasks = cell(10,1);
onCleanupTasks{10} = onCleanup(@() diary('off'));
disp(cfg);

% --- Optional: parallel worker for external audio recording ---
%if isempty(gcp('nocreate'))
    %parpool('local',1);
%end
%workerQueueConstant = parallel.pool.Constant(@parallel.pool.PollableDataQueue);
%workerQueueClient   = fetchOutputs(parfeval(@(x) x.Value, 1, workerQueueConstant));

% Add code paths and change to scripts directory inside the task repo
if isfolder(cfg.PATH_TASK)
    addpath(genpath(cfg.PATH_TASK));
    scriptsDir = fullfile(cfg.PATH_TASK,'scripts');
    if isfolder(scriptsDir)
        cd(scriptsDir);
    else
        warning('Scripts folder not found at %s; using current directory.', scriptsDir);
    end
else
    warning('cfg.PATH_TASK does not exist: %s', cfg.PATH_TASK);
end

% Launch background audio recorder used in both preop/intraop flows
if ~(exist('record_audio_preop','file')==2)
    clear onCleanupTasks
    error('record_audio_preop() not found on path.');
end
%future = parfeval(@record_audio_preop, 1, cfg.AUDIO_FILENAME, workerQueueConstant);
%future.Diary;
%onCleanupTasks{6} = onCleanup(@() send(workerQueueClient, 'stop'));

% --- No digital I/O / Ripple in DAF ---
cfg.DIGOUT = 0;

% --- Launch task (non-PTB) ---
fprintf('Launching task\n');

task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function)
    clear onCleanupTasks
    error('%s should be in current working directory', cfg.TASK_FUNCTION);
end
copyfile(task_function, [cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']);

task_daf(cfg);

% --- Cleanup ---
clear onCleanupTasks;
close all;
