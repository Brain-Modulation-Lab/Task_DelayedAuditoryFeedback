  % Launcher script for DAF Task - Nomad-style intraop
clear;
figure

cfg=[];

cfg.SUBJECT = 'test0715';
cfg.SESSION_LABEL = 'intraop';
cfg.DATA_TYPE = 'task';

cfg.SPEECH_LEVEL_THR=0.025;

cfg.DB_SENTENCES_TSV = 'daf_sentences.tsv';

cfg.DAF.delay_options_ms = [150];
cfg.DAF.catch_ratio = 0.0;
cfg.DAF.max_delay_ms = 1000;

cfg.HOST_AUDIO_API_NAME = 'Windows WASAPI';
cfg.SCREEN_RES = [1280 1024];

if strcmpi('BML-ALIENWARE',getenv('COMPUTERNAME'))
    cfg.PATH_TASK = 'D:\docs\code\stut_obs\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = 'C:\ieeg_stut';
    cfg.AUDIO_DEVICE = 'Speakers/Headphones (Realtek(R) Audio)';
elseif strcmpi('BML-ALIENWARE2',getenv('COMPUTERNAME'))
    cfg.PATH_TASK = 'D:\docs\code\stut_obs\Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = 'C:\ieeg_stut';
    cfg.AUDIO_DEVICE = 'Speakers (Realtek(R) Audio)';
else
    cfg.PATH_TASK = '~/git/Task_DelayedAuditoryFeedback';
    cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata';
end

cfg.TEST_SOUND_S = 10;
cfg.CALIBRATION_BEEPS_N = 5;

cfg.AUDIO_AMP = 1;
cfg.GO_BEEP_AMP = 0.5;
cfg.KEYBOARD_ID = [];
cfg.SKIP_SYNC_TEST = 1;
cfg.CONSERVE_VRAM_MODE = 4096;

cfg.TASK = 'daf';
cfg.TASK_VERSION = 1;
cfg.TASK_FUNCTION = 'teask_delayeduditoryfeedback.m';

cfg.audio_sample_rate = 44100;
cfg.audio_frame_size = 128;
cfg.audio_playback_gain = 15;
cfg.fix_cross_dur = 0.;
cfg.delay_dur = 0.;
cfg.text_stim_dur = 12.0;
cfg.iti = 2.0;
cfg.stim_font_size = 65;
cfg.stim_max_char_per_line = 38;

if isempty(gcp())
    parpool('local', 1);
    wait();
end

workerQueueConstant = parallel.pool.Constant(@parallel.pool.PollableDataQueue);
workerQueueClient = fetchOutputs(parfeval(@(x) x.Value, 1, workerQueueConstant));

warning('on','all');
beep off
PsychDefaultSetup(2);

pathSub = [cfg.PATH_SOURCEDATA filesep 'sub-' cfg.SUBJECT];
pathSubSes = [pathSub filesep 'ses-' cfg.SESSION_LABEL];
pathSubSesDataType = [pathSubSes filesep cfg.DATA_TYPE];
pathSubSesAudio = [pathSubSes filesep 'audio'];
cfg.PATH_AUDIO = pathSubSesAudio;

if ~isfolder(cfg.PATH_SOURCEDATA)
    error('sourcedata folder %s does not exist',cfg.PATH_SOURCEDATA)
end
if ~isfolder(pathSub), mkdir(pathSub); end
if ~isfolder(pathSubSes), mkdir(pathSubSes); end
if ~isfolder(pathSubSesDataType), mkdir(pathSubSesDataType); end
if ~isfolder(pathSubSesAudio), mkdir(pathSubSesAudio); end

fileBaseName = ['sub-' cfg.SUBJECT '_ses-' cfg.SESSION_LABEL '_task-' cfg.TASK '_run-'];

allEventFiles = dir([pathSubSesDataType filesep fileBaseName '*_events.tsv']);
if ~isempty(allEventFiles)
    prevRunIds = regexp({allEventFiles.name}, '_run-(\d+)_','tokens','ignorecase','forceCellOutput','once');
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
cfg.TRIAL_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'trials.tsv'];
cfg.AUDIO_CALIBRATION_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'audio-calibration.mat'];

stimPath = fullfile(cfg.PATH_TASK, 'Stimuli', cfg.DB_SENTENCES_TSV);
if ~isfile(stimPath)
    error('Sentences TSV not found: %s', stimPath);
end
T = readtable(stimPath, 'FileType','text', 'Delimiter','\t', 'ReadVariableNames', false);
sentences = string(T{:,1});
nSentences = numel(sentences);
delays = cfg.DAF.delay_options_ms(:)';
if any(delays > cfg.DAF.max_delay_ms)
    error('One or more delay_options_ms exceed the maximum allowed delay of %d ms.', cfg.DAF.max_delay_ms);
end
[sIdx,dIdx] = ndgrid(1:nSentences, 1:numel(delays));
allSentIdx = sIdx(:);
allDelayVal = delays(dIdx(:));
order = randperm(numel(allSentIdx));
allSentIdx = allSentIdx(order);
allDelayVal = allDelayVal(order);
nTrials = numel(allSentIdx);
catchRatio = cfg.DAF.catch_ratio;
nCatch = round(nTrials * catchRatio);
isCatch = false(nTrials,1);
if nCatch > 0
    isCatch(randperm(nTrials, nCatch)) = true;
end
sentence_id = allSentIdx;
text = sentences(sentence_id);
delay_ms = allDelayVal(:);
trial_type = repmat("speech", nTrials, 1);
trial_type(isCatch) = "catch";
stim_epoch  = repmat("nostim", nTrials, 1);
dbTrials = table(sentence_id, text, delay_ms, trial_type, stim_epoch);
dbTrials.file_text = text;
dbTrials.file_audio = repmat("", height(dbTrials), 1);

cfg.TRIAL_TABLE = dbTrials;

diary(cfg.LOG_FILENAME);
onCleanupTasks = cell(10,1);
onCleanupTasks{10} = onCleanup(@() diary('off'));
fprintf('\nConfiuration struture:\n');
disp(cfg)

cfg.AUDIO_FILENAME = [cfg.PATH_AUDIO filesep cfg.BASE_NAME(1:end-1) '.wav'];

filename = cfg.AUDIO_FILENAME;
if exist('record_audio','file')==2
    future = parfeval(@record_audio, 1, filename, workerQueueConstant);
    future.Diary;
    onCleanupTasks{6} = onCleanup(@() send(workerQueueClient, 'stop'));
else
    warning('record_audio() function not found. Skipping background audio recording.');
end

cfg.DIGOUT = 0;

fprintf('Launching task');

writetable(dbTrials,cfg.TRIAL_FILENAME,'Delimiter','\t','FileType','text');

task_function = [pwd filesep cfg.TASK_FUNCTION];
if ~isfile(task_function)
    clear onCleanupTasks
    error('%s should be in current working directory',cfg.TASK_FUNCTION);
end
copyfile(task_function,[cfg.PATH_LOG filesep cfg.BASE_NAME 'script.m']);

teask_delayeduditoryfeedback(cfg);

clear onCleanupTasks;
close all;