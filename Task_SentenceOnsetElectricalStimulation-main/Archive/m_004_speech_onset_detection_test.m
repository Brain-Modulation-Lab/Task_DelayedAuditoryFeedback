
function m_004_speech_onset_detection_test(cfg)

%close all
%clear all
%clc

%opening events file
eventFile = fopen(cfg.EVENT_FILENAME, 'a');  % Appending mode
onCleanupTasks{19} = onCleanup(@() fclose(eventFile));
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n'); %BIDS event file in system time coord

log_event(eventFile, cfg.DIGOUT, [], 0, [], [], [], 0, 'Initializing',0);

detection_ops.loudness_threshold =.1; % range 0 to 1
detection_ops.max_dur_seconds = inf; % don't timeout the detection function
recording_device_index = 11; 
playback_device_index = 4; 
pa_reqlatencyclass = 1; % set to 1 to not force low latency
pa_freq = []; % use default frequency
reallyneedlowlatency = 0; %%% set to true to force psychportaudio to get very low latency

% recording parameters
detection_ops.waitscan_seconds = 0.01; % wait this long between recording scans
suggested_latency_seconds = 0.02; % 'suggestedLatency' to input to PsychPortAudio(‘Open’)
n_rec_chans = 2; % number of recording channels
allocated_record_seconds = 1; % 'amountToAllocateSecs' to input to PsychPortAudio(‘GetAudioData’)

% playback parameters
playback_when = 0; % start playback immediately
playback_repetitions = 1; 
playback_waitForStart = 1; 
n_playback_channels = 2; 
InitializePsychSound(reallyneedlowlatency);
PsychPortAudio('Close',[]); % close any devices that were left open
recording_handle = PsychPortAudio('Open', recording_device_index, 2, pa_reqlatencyclass, pa_freq, n_rec_chans, [], suggested_latency_seconds);
PsychPortAudio('GetAudioData', recording_handle, allocated_record_seconds); % initialize recording device with buffer

% start recording
detection_ops.recording_repeititions = 0; % loop indefinitely until detection
detection_ops.recording_when = 0; % start immediately

% wait until voice detected, then continue
speech_onset_detection(recording_handle, ...
    detection_ops); 

log_event(eventFile, cfg.DIGOUT, [], 0.25, [], [], [], 255, 'Trigger test',1);

disp('speech onset identified')