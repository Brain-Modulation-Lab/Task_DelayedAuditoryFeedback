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
%
% -------------------------------------------------------------------------
%
% -------------------------------------------------------------------------
% If creating all presets on hardware (NO ECLIPSEMIDICOMM)
%
% STEP 1 — Put Eclipse into a usable starting state
% 1) On the Eclipse front panel:
%    - Turn the top left PARAMETER knob (or use arrow keys) until you see the "PROGRAM" page
%    - Press the PROGRAM soft key to enter program selection mode
% 2) Pick "Mono Delay"
% 
% STEP 2 — Create the 0 ms DAF preset (DAF_0ms)
% 1) Press PARAMETER to enter editing
% 2) Navigate parameters using the encoder and arrow keys.
% 3) Set the key parameters:
%    - Delay Time: 0 ms
%    - Feedback: 0
%    - Mix: 100% wet
%    - Output Level / Main Level: leave at a comfortable/standard value
%    - Bypass: make sure the effect is active (not bypassed)
%    - Routing: leave as default unless special routing is needed
% 
% 4) Press the SOFT KEY labeled "STORE" (often soft key 4 under the screen)
% 5) When prompted "Store Program To:", use the arrow keys to pick an empty slot
%    (e.g., Program 201)
% 6) Press ENTER.
% 7) Name the preset (recommended): DAF_0ms
% 8) Press ENTER to confirm.
% 9) Record preset below in cfg.PRESET_MAP
% 
% STEP 3 — Create a DAF preset at a non-zero delay (e.g., 200 ms)
% 
% For each delay you want (e.g., 150 ms, 200 ms, 250 ms), repeat:
% 
% 1) Press PROGRAM and select your saved DAF_0ms preset (Program 201).
% 2) Press PARAMETER to edit.
% 3) Change:
%    - Delay Time: e.g., 200 ms
%      (You can either use the encoder knob or the keypad sequence such as:
%       HOTKEY → PROGRAM → K2 → K0 → K0 → ENTER → SOFT4 to load)
%    - Feedback: keep at 0
%    - Mix: typically same as 0 ms preset (e.g., 100% wet)
% 
% 4) Press STORE.
% 5) Choose an empty slot, e.g., Program 202.
% 6) Name it, e.g.: DAF_200ms
% 7) Press ENTER to confirm.
% 8) Record preset below in cfg.PRESET_MAP
% 
% Repeat STEP 3 for each delay value in the experiment and add each one to cfg.PRESET_MAP
% -------------------------------------------------------------------------
%
% -------------------------------------------------------------------------
% If using EclipseMidiComm:
%
% STEP 1: Create a CLEAN_PASS program (no DAF, neutral effect)
% (This is what Eclipse runs after the experiment)
%
% 1) Load a neutral / clean program (e.g. "Thru", "Bypass", or equivalent).
% 2) Press PARAMETER to edit if necessary.
% 3) Adjust parameters so audio is effectively unaffected:
%       - Delay Time: 0 ms
%       - Feedback: 0
%       - Mix: 0% wet or equivalent "no effect" setting
%       - Bypass: ON or equivalent
%       - Output Level: comfortable working level
% 4) Store this as a new program:
%       - Press STORE
%       - Choose an empty program slot, e.g. Program 100.
%       - Press ENTER.
%       - Name it CLEAN_PASS
%       - Press ENTER again to confirm.
% 5) Record this program number in the MATLAB script:
%       cfg.ECLIPSE.cleanProgramNum = 100;
%
% -------------------------------------------------------------------------
% STEP 2: Create the DAF_BASE program (0 ms delay, ready for remote control)
% (This is the ONLY DAF program needed EclipseMIDIcomm will change its delay)
%
% 1) Load a delay capable base program
% 2) Press PARAMETER to enter edit mode
% 3) Adjust core parameters:
%       - Delay Time: 0 ms
%       - Feedback: 0
%       - Mix: 100% wet (or protocol value for DAF)
%       - Bypass: OFF (effect engaged)
%       - Routing: default unless your setup requires special routing
% 4) Store this as your DAF base program:
%       - Press STORE.
%       - Choose an empty program slot, e.g. Program 201.
%       - Press ENTER.
%       - Name it DAF_BASE
%       - Press ENTER again to confirm.
% 5) Record this program number in the MATLAB script:
%       cfg.ECLIPSE.dafProgramNum = 201;
% -------------------------------------------------------------------------

%% Setup experiment configuration
cfg = struct();
cfg.SESSION_LABEL = 'intraop';      % Label for session type (e.g., intraop, preop)
cfg.SUBJECT       = 'daftestsub';   % Subject identifier
cfg.DATA_TYPE     = 'task';         % Data type for folder structure
cfg.RECORD_AUDIO  = false;          % Whether to record microphone audio during the task
cfg.PTB           = false;          % Use Psychtoolbox for timing and display (false disables it)
cfg.STOP_BETWEEN_TRIALS = 0;     % Require space to proceed between all trials (after ITI plays)
% ----------------------------------
cfg.MIDI_CHANNEL  = 1;              % Set to MIDI channel as per hardware
cfg.MIDI_OUT_NAME = 'M-Audio MIDISPORT Uno';      % name of Stepp Lab usb-to-midi adapter from mididevinfo.m
% if you don't know this name, run mididevinfo
% ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

% Task metadata
cfg.TASK          = 'daf';              % Task name
cfg.TASK_VERSION  = 1;                  % Version number
cfg.TASK_FUNCTION = 'task_daf_MIDI.m';  % Task main function filename

% Core DAF parameters
cfg.max_trials             = inf;     % Maximum number of trials (inf = unlimited)
cfg.text_stim_dur          = 10;      % Duration to show text stimulus on screen (seconds)
cfg.stim_font_size         = 50;      % Font size of stimulus text
cfg.stim_max_char_per_line = 30;      % Maximum characters per line in stimulus text
cfg.catchRatio             = 0;       % Probability of catch trials (no auditory feedback)
cfg.max_stim_repeats       = 2;       % Max number of repeats per stimulus
cfg.max_delay_repeats      = 4;       % Max repeats per delay condition
cfg.same_trials_across_blocks = true; % Use same trials repeated across blocks
cfg.DAF_START_OFFSET_S = 0.000;       % Optional time offset between fixation and DAF start

% Stimulus sentences file per session
cfg.daf_stim_file = 'daf_sentences_extra_alliteration.tsv';

% Set delay values and number of blocks according to session type
switch cfg.SESSION_LABEL
    case 'preop'
        cfg.delay_values_ms = [0 100 150 200 250];
        cfg.n_blocks = 2;
    case 'intraop'
        cfg.delay_values_ms = [0 5];
        cfg.n_blocks = 4;
    otherwise
        error('Unknown session label: %s', cfg.SESSION_LABEL);
end

%% MIDI setup
try
    devs = mididevinfo;
catch
    error(['mididevinfo not found. Ensure MATLAB supports MIDI on this installation ','(Instrument Control Toolbox or Audio Toolbox w/ MIDI).']);
end

outNames = string({devs.output.Name});
ix = find(contains(lower(outNames), lower(cfg.MIDI_OUT_NAME), 'IgnoreCase', true), 1);

if isempty(ix)
    warning('MIDI out "%s" not found. Available: %s', cfg.MIDI_OUT_NAME, strjoin(outNames, ', '));
    cfg.DAF_MIDI = []; % allow visuals only fallback
else
    cfg.DAF_MIDI = mididevice('Output', outNames(ix));

    %%%%%%%%%%%%%%%%%%% UNCOMMENT OUT BLOCK IF USING ECLIPSEMIDICOMM
    % Initialize EclipseMIDIcomm
    deviceName = outNames(ix);
    cfg.ECLIPSE = struct();
    cfg.ECLIPSE.hcom            = EclipseMIDIcomm(deviceName);
    cfg.ECLIPSE.cleanProgramNum = 1;  % ****** set to custom DafOff (sound playback w/o DAF program) program number
    cfg.ECLIPSE.dafProgramNum   = 1;  % ****** set to custom DAF program number
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
if isempty(cfg.DAF_MIDI)
    warning('Running WITHOUT DAF (no MIDI device). Visuals/logging only.');
end

% Create delay mapping
delays = int32(round(cfg.delay_values_ms(:)')); % row vector of delay keys

%%%%%%%%% FILL THESE IN TO MATCH THE FRONT PANEL PRESET SLOTS %%%%%%%%%%%%%%
% Example: 0 ms stored at program 201, 150 ms at 202
presetNums = [3 3];    % <--- CHANGE THIS to your actual program numbers
% AM needs to make sure that presets for delays specified above match the numbers in num2cell in fllowing line... these presets are manually created on the devices control pannel, not in this script

cfg.PRESET_MAP = containers.Map(num2cell(delays), num2cell(presetNums));

% Ensure all delays have a preset
assert(all(isKey(cfg.PRESET_MAP, num2cell(delays))), 'PRESET_MAP must cover all cfg.delay_values_ms.');

%% Parallel pool for optional audio recording (master)
if cfg.RECORD_AUDIO && isempty(gcp('nocreate'))
    parpool('local',1);
end
if cfg.RECORD_AUDIO
    workerQueue = parallel.pool.PollableDataQueue;
    workerQueueConstant = parallel.pool.Constant(workerQueue);
end

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

%% Change to scripts folder
scriptPath = fullfile(cfg.PATH_TASK, 'scripts');
if ~isfolder(scriptPath)
    error('Scripts folder not found: %s', scriptPath);
end
cd(scriptPath);

%% Start audio recording (optional)
if cfg.RECORD_AUDIO
    if ~(exist('record_audio','file')==2)
        error('record_audio() not found on path.');
    end
    future = parfeval(@record_audio, 1, cfg.AUDIO_FILENAME, workerQueueConstant); % Launch async audio recording task with queue for communication
    future.Diary;
    recCleanup = onCleanup(@() send(workerQueue, 'stop'));
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