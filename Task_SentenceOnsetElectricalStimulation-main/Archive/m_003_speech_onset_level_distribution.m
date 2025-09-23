
close all
clear all
clc

%% Creating configuration structure
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
%% 

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
% detection_ops.loudness_threshold = cfg.SPEECH_LEVEL_THR; % range 0 to 1
detection_ops.max_dur_seconds = 5; % don't timeout the detection function
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

%%




% detection_ops.loudness_threshold = .001; % range 0 to 1
% detection_ops.max_dur_seconds = inf; % don't timeout the detection function
% recording_device_index = 11; 
% playback_device_index = 4; 
% pa_reqlatencyclass = 1; % set to 1 to not force low latency
% pa_freq = []; % use default frequency
% reallyneedlowlatency = 0; %%% set to true to force psychportaudio to get very low latency
% % recording parameters
% detection_ops.waitscan_seconds = 0.01; % wait this long between recording scans
% suggested_latency_seconds = 0.02; % 'suggestedLatency' to input to PsychPortAudio(‘Open’)
% n_rec_chans = 2; % number of recording channels
% allocated_record_seconds = 1; % 'amountToAllocateSecs' to input to PsychPortAudio(‘GetAudioData’)
% 
% % playback parameters
% playback_when = 0; % start playback immediately
% playback_repetitions = 1; 
% playback_waitForStart = 1; 
% n_playback_channels = 2; 
% InitializePsychSound(reallyneedlowlatency);
% PsychPortAudio('Close',[]); % close any devices that were left open
% recording_handle = PsychPortAudio('Open', recording_device_index, 2, pa_reqlatencyclass, pa_freq, n_rec_chans, [], suggested_latency_seconds);
% PsychPortAudio('GetAudioData', recording_handle, allocated_record_seconds); % initialize recording device with buffer
% 
% % start recording
% detection_ops.recording_repeititions = 0; % loop indefinitely until detection
% detection_ops.recording_when = 0; % start immediately


% wait until voice detected, then continue
for ii=1:10
    levels(ii)=speech_onset_detection(recording_handle, detection_ops); 
    disp('speech onset identified')
    ii;
end

histogram(levels)
