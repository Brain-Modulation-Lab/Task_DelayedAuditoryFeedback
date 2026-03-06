function start_daf_intraop_MIDI
% start_daf_intraop_MIDI - Intraoperative launcher for the Delayed Auditory Feedback (DAF) task
%
% This function configures and launches task_daf_MIDI, which controls
% the experiment presentation, timing, and communication with the H90 Eventide.
% It sets default parameters, prepares paths and logging filenames, initializes
% optional audio recording and hardware interfaces, and launches the task script.
%
% No input arguments; all configuration is inside the function.
%
% The configuration is stored in the 'cfg' struct, passed to the task function.


% -------------------------------------------------------------------------

%% Setup experiment configuration
cfg = struct();

cfg.SUBJECT       = 'DM1055';   % Subject identifier

% cfg.SESSION_LABEL = 'preop';      % Label for session type (e.g., intraop, preop)
cfg.SESSION_LABEL = 'intraop'; 

cfg.DATA_TYPE     = 'task';         % Data type for folder structure
cfg.RECORD_AUDIO  = 1;          % Whether to record microphone audio during the task
cfg.PTB           = false;          % Use Psychtoolbox for timing and display (false disables it)
cfg.STOP_BETWEEN_TRIALS = 1;     % Require space to proceed between all trials (after ITI plays)
% ----------------------------------
cfg.midi_dev_name = 'H90 Pedal';      % name of Stepp Lab usb-to-midi adapter from mididevinfo.m
cfg.midi_chan  = 1;              % Set to MIDI channel as per hardware... should have been pre-set on the midi device
cfg.midi_cc_num = 1;        % MIDI control change number .... should have been pre-set on the midi device

% Task metadata
cfg.TASK          = 'daf';              % Task name
cfg.TASK_VERSION  = 2;                  % Version number
cfg.TASK_FUNCTION = 'task_daf_MIDI.m';  % Task main function filename

% Core DAF parameters
cfg.max_trials             = inf;     % Maximum number of trials (inf = unlimited)
cfg.text_stim_dur          = 10;      % Duration to show text stimulus on screen (seconds)
cfg.stim_font_size         = 60;      % Font size of stimulus text
cfg.stim_max_char_per_line = 30;      % Maximum characters per line in stimulus text
cfg.catchRatio             = 0;       % Probability of catch trials (no auditory feedback)
cfg.max_stim_repeats       = 2;       % Max number of repeats per stimulus
cfg.max_delay_repeats      = 4;       % Max repeats per delay condition
cfg.same_trials_across_blocks = true; % Use same trials repeated across blocks
cfg.DAF_START_OFFSET_S = 0.000;       % Optional time offset between fixation and DAF start

%%%%%% Stimulus sentences file per session
% cfg.daf_stim_file = 'daf_sentences_extra_alliteration.tsv';


% Set delay values and number of blocks according to session type
switch cfg.SESSION_LABEL
    case 'preop'
        cfg.delay_values_ms = [0 50 100 150]; % 
        cfg.n_blocks = 2;
        cfg.daf_stim_file = 'daf_sentences_preop.tsv';
    case 'intraop'
        cfg.delay_values_ms = [0 150];
%         cfg.delay_values_ms = [0 100 150 200];
        cfg.n_blocks = 4;
        cfg.daf_stim_file = 'daf_sentences_intraop.tsv';
    otherwise
        error('Unknown session label: %s', cfg.SESSION_LABEL);
end

clc
close all force

%% MIDI setup
try
    devs = mididevinfo;
catch
    error(['mididevinfo not found. Ensure MATLAB supports MIDI on this installation ','(Instrument Control Toolbox or Audio Toolbox w/ MIDI).']);
end

outNames = string({devs.output.Name});
ix = find(contains(lower(outNames), lower(cfg.midi_dev_name), 'IgnoreCase', true), 1);

if isempty(ix)
    warning('MIDI out "%s" not found. Available: %s', cfg.midi_dev_name, strjoin(outNames, ', '));
    cfg.midi_dev_idx = []; % allow visuals only fallback
else
    cfg.midi_dev_idx = mididevice('Output', outNames(ix));
end

% Log a quick probe for audit
fprintf('[MIDI] Outputs available:\n');
for i = 1:numel(outNames)
    sel = "";
    if i == ix
        sel = "  [SELECTED]";
    end
    fprintf('  - %s%s\n', outNames(i), sel);
end
if isempty(cfg.midi_dev_idx)
    warning('Running WITHOUT DAF (no MIDI device). Visuals/logging only.');
end

% % % %% Parallel pool for optional audio recording (master)
% % % if cfg.RECORD_AUDIO && isempty(gcp('nocreate'))
% % %     parpool('local',1);
% % % end
% % % if cfg.RECORD_AUDIO
% % %     workerQueue = parallel.pool.PollableDataQueue;
% % %     workerQueueConstant = parallel.pool.Constant(workerQueue);
% % % end

%% Paths & output folders
if strcmpi(getenv('COMPUTERNAME'), 'BML-ALIENWARE2') % intraop rig laptop
    cfg.PATH_TASK       = 'D:\Task\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata';

elseif strcmpi(getenv('COMPUTERNAME'), '677-GUE-WL-0010') % A Meier work laptop
    cfg.PATH_TASK       = 'C:\docs\code\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = 'C:\sourcedata'; 

elseif ismac
    cfg.PATH_TASK       = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/';
    cfg.PATH_SOURCEDATA = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/stimuli';
else
    cfg.PATH_TASK       = '~/git/Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata';
end
cfg.PATH_STIMDIR = [cfg.PATH_TASK, filesep, 'stimuli']; 

% Build subject/session level folders for data storage
pathSub = fullfile(cfg.PATH_SOURCEDATA, ['sub-' cfg.SUBJECT]);
pathSubSes = fullfile(pathSub, ['ses-' cfg.SESSION_LABEL]);
pathSubSesDataType = fullfile(pathSubSes, cfg.DATA_TYPE);
pathSubSesAudio = fullfile(pathSubSes, 'audio');

% Create output directories if they do not exist
for p = {cfg.PATH_SOURCEDATA, pathSub, pathSubSes, pathSubSesDataType, pathSubSesAudio}
    if ~isfolder(p{1}), mkdir(p{1}); end
end
cfg.PATH_AUDIO = pathSubSesAudio;



%% Run basename, filenames
fileBaseName  = ['sub-' cfg.SUBJECT '_ses-' cfg.SESSION_LABEL '_task-' cfg.TASK '_run-'];

% Check existing event files to increment run ID for this session
allEventFiles = dir(fullfile(pathSubSesDataType, [fileBaseName '*_events.tsv']));
if ~isempty(allEventFiles)
    prevRunIds = regexp({allEventFiles.name}, '_run-(\d+)_', 'tokens', 'ignorecase');
    prevRunIds = cellfun(@(x) str2double(x{1,1}), prevRunIds, 'UniformOutput', true);
    runId = max(prevRunIds) + 1;
else
    runId = 1;
end

% Assign run ID and generate file paths for logs and audio
cfg.RUN_ID = runId;
cfg.PATH_LOG = pathSubSesDataType;
cfg.BASE_NAME = [fileBaseName, sprintf('%02d_', runId)];
cfg.LOG_FILENAME = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'log.txt']);
cfg.EVENT_FILENAME = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'events.tsv']);
cfg.TRIAL_FILENAME = fullfile(cfg.PATH_LOG, [cfg.BASE_NAME 'trials.tsv']);
cfg.AUDIO_FILENAME = fullfile(cfg.PATH_AUDIO, [cfg.BASE_NAME(1:end-1) '.wav']);

%% Start MATLAB diary for logging console output to log file
diary(cfg.LOG_FILENAME);
oc = onCleanup(@() diary('off')); % Ensure diary is turned off when function exits
disp(cfg);  % Display config for verification

%% Start audio recording (optional)
% parallel worker for external audio recording (same pattern as preop) ---
if isempty(gcp())
    parpool('local',1);
end
workerQueueConstant = parallel.pool.Constant(@parallel.pool.PollableDataQueue);
workerQueueClient   = fetchOutputs(parfeval(@(x) x.Value, 1, workerQueueConstant));

%% Change to scripts folder
scriptPath = fullfile(cfg.PATH_TASK, 'scripts');
if ~isfolder(scriptPath)
    error('Scripts folder not found: %s', scriptPath);
end
cd(scriptPath);

% Use same worker name as preop for parity (or swap to your preferred worker)
if strcmp (cfg.SESSION_LABEL,'preop')
    if ~(exist('record_audio_preop','file')==2)
        clear onCleanupTasks
        error('record_audio_preop() not found on path.');
    end
    future = parfeval(@record_audio_preop, 1, cfg.AUDIO_FILENAME, workerQueueConstant);
    future.Diary;
    onCleanupTasks{6} = onCleanup(@() send(workerQueueClient, 'stop'));
elseif strcmp (cfg.SESSION_LABEL,'intraop')
    future = parfeval(@record_audio, 1, cfg.AUDIO_FILENAME, workerQueueConstant);
    future.Diary;
    onCleanupTasks{6} = onCleanup(@() send(workerQueueClient, 'stop'));
end

%% Ripple neurophysiology hardware communication setup (optional)
cfg.DIGOUT = 0;
if exist('xippmex','file')==3
    try
        digout = xippmex();  % Initialize hardware interface
        cfg.DIGOUT = digout ~=0;
        xippmexCleanup = onCleanup(@() xippmex('close'));
    catch err
        warning('xippmex init failed: %s', err.MESSAGE);
    end
end

%% Launch task
fprintf('Launching task\n');
task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function)
    error('%s not found in current folder', cfg.TASK_FUNCTION);
end
copyfile(task_function, [cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']); % Copy the task function file to the log folder for reproducibility
feval(strrep(cfg.TASK_FUNCTION,'.m',''), cfg); % Execute the task function, passing full config struct

close all;
end