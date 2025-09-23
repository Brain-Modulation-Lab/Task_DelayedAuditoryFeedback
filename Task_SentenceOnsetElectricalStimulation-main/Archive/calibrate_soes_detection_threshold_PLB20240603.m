
function [] = calibrate_soes_detection_threshold(cfg)

% %% Creating configuration structure
% % Copied and modified from START_SOES_INTRAOP, Latane Bullock 2024 06 03
% cfg=[];
%                                        
% % subject and session
% cfg.SUBJECT = 'testAB0531' ; %subject identifier
% cfg.SESSION_LABEL = 'intraop'; %type of session ('test', 'training', 'preop', 'intraop')
% cfg.DATA_TYPE = 'task'; %BIDS data type 'beh' for behavioral and task data. 
% 
% 
% % hardware settings
% cfg.SCREEN_SYNC_RECT = [0 0 20 20]; %rectangle used for screen sync
% cfg.SCREEN_SYNC_COLOR = [255 255 255];
%   
% % Paths and configurations
% cfg.HOST_AUDIO_API_NAME = 'Windows WASAPI';
% cfg.SCREEN_RES = [1280 1024]; % Screen resolution
% cfg.SCALE_FONT = 1;
% 
% cfg.MIC_API_NAME = 'Windows WASAPI';%MRR
% 
% if strcmpi('BML-ALIENWARE',getenv('COMPUTERNAME'))
%     cfg.PATH_TASK = 'D:\Task\Task_SentenceOnsetElectricalStimulation';
%     cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata'; %source data root folder 
%     cfg.AUDIO_DEVICE = 'Speakers (Radial USB Pro)';
%     cfg.MIC_DEVICE = 'Analogue 1 + 2 (2- Focusrite USB Audio)';
%     cfg.SCREEN_ID = 3;
% elseif strcmpi('BML-ALIENWARE2',getenv('COMPUTERNAME'))
%     cfg.PATH_TASK = 'D:\Task\Task_SentenceOnsetElectricalStimulation';
%     cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata'; %source data root folder 
%     cfg.AUDIO_DEVICE = 'Speakers (Radial USB Pro)';
%     cfg.MIC_DEVICE = 'Analogue 1 + 2 (2- Focusrite USB Audio)';
%     cfg.SCREEN_ID = 2;
% else
%     cfg.PATH_TASK = '~/git/Task_SentenceOnsetElectricalStimulation'; 
%     cfg.PATH_SOURCEDATA = '~/Data/DBS/sourcedata'; %source data root folder 
% end
% 
% cfg.TEST_SOUND_S = 10; %duration (in seconds) of sound for volume adjustment
% cfg.CALIBRATION_BEEPS_N = 5; %number of calibration beeps to play
% 
% cfg.AUDIO_AMP = 1;
% cfg.GO_BEEP_AMP = 0.5; 
% cfg.KEYBOARD_ID = []; % prefered keyboard 
% cfg.SKIP_SYNC_TEST = 1; %should screen test be skipped (use only for debugging)
% cfg.CONSERVE_VRAM_MODE = 4096; %kPsychUseBeampositionQueryWorkaround
% 
% 
% % Task Stimulation parameters
% cfg.TASK = 'sent_onset_stim'; % name of current task
% cfg.TASK_VERSION = 1; % version number for task
% cfg.TASK_FUNCTION = 'task_sent_onset_stim.m';
% 
% %% More path setup
% % Copied and modified from START_SOES_INTRAOP, Latane Bullock 2024 06 03
% 
% % checking data path
% pathSub = [cfg.PATH_SOURCEDATA filesep 'sub-' cfg.SUBJECT];
% pathSubSes = [pathSub filesep 'ses-' cfg.SESSION_LABEL];
% pathSubSesDataType = [pathSubSes filesep cfg.DATA_TYPE];
% pathSubSesAudio = [pathSubSes filesep 'audio'];
% cfg.PATH_AUDIO = pathSubSesAudio;
% 
% if ~isfolder(cfg.PATH_SOURCEDATA)
%     error('sourcedata folder %s does not exist',cfg.PATH_SOURCEDATA)
% end
% if ~isfolder(pathSub)
%     fprintf('Creating subject folder %s \n',pathSub)
%     mkdir(pathSub)
% end
% if ~isfolder(pathSubSes)
%     fprintf('Creating session folder %s \n',pathSubSes)
%     mkdir(pathSubSes)
% end
% if ~isfolder(pathSubSesDataType)
%     fprintf('Creating session folder %s \n',pathSubSesDataType)
%     mkdir(pathSubSesDataType)
% end
% if ~isfolder(pathSubSesAudio)
%     fprintf('Creating session folder %s \n',pathSubSesAudio)
%     mkdir(pathSubSesAudio)
% end
% 
% % creating files basename 
% fileBaseName = ['sub-' cfg.SUBJECT '_ses-' cfg.SESSION_LABEL '_task-' cfg.TASK '_run-'];
% 
% %checking for previous runs based PBT events file
% allEventFiles = dir([pathSubSesDataType filesep fileBaseName '*_events.tsv']);
% if ~isempty(allEventFiles)
%     prevRunIds = regexp({allEventFiles.name}, '_run-(\d+)_' ,'tokens','ignorecase','forceCellOutput','once');
%     prevRunIds = cellfun(@(x) str2double(x{1,1}),prevRunIds,'UniformOutput',true);
%     runId = max(prevRunIds) + 1;
% else
%     runId = 1;
% end
% 
% cfg.RUN_ID = runId;
% cfg.PATH_LOG = pathSubSesDataType;
% cfg.BASE_NAME = [fileBaseName num2str(cfg.RUN_ID,'%02.f') '_'];
% cfg.LOG_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'log.txt'];
% cfg.EVENT_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'events.tsv'];
% cfg.TRIAL_FILENAME = [cfg.PATH_LOG filesep cfg.BASE_NAME 'trials.tsv']; % randomized trials info


% %% Psychtoolbox setup
% % Copied and modified from START_SOES_INTRAOP, Latane Bullock 2024 06 03
% 
% fprintf('Initializing psychtoolbox at %s for subject %s, %s task, session %s, run %i\n\n',datestr(now,'HH:MM:SS'),cfg.SUBJECT,cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID);
% 
% % Initializing Keyboard
% fprintf('Initializing Keyboard...'); 
% if isempty(cfg.KEYBOARD_ID)
%     fprintf('\nNo keyboard selected, using default. Choose KEYBOARD_ID from this table:\n'); 
%     % Detect keyboards attached to system
%     devices = struct2table(PsychHID('Devices'));  
%     disp(devices);
% end
% 
% KbName('UnifyKeyNames')
% keyCodeEscape = KbName('ESCAPE');
% fprintf('done\n'); 
% 
% % Initialize Sound
% fprintf('Initializing Sound...\n'); 
% PsychDefaultSetup(2);
% InitializePsychSound; 
% 
% % getting audio device id
% pa_devices = struct2table(PsychPortAudio('GetDevices'));
% pa_devices_sel = contains(pa_devices.HostAudioAPIName,cfg.HOST_AUDIO_API_NAME) & contains(pa_devices.DeviceName,cfg.AUDIO_DEVICE); 
% if sum(pa_devices_sel) == 0 
%     disp(pa_devices);
%     error('%s - %s not found. Choose one from the list of available audio devices',cfg.HOST_AUDIO_API_NAME,cfg.AUDIO_DEVICE);
% elseif sum(pa_devices_sel) > 1
%     disp(pa_devices);
%     error('%s - %s matches more than one device. Choose one from the list of available audio devices',cfg.HOST_AUDIO_API_NAME,cfg.AUDIO_DEVICE);
% else
%     fprintf('The following audio device was selected');
%     disp(pa_devices(pa_devices_sel,:));
%     cfg.AUDIO_ID = pa_devices.DeviceIndex(pa_devices_sel);
% end
% pa_mode = 1+8; %1 == sound playback only; 8 == openning as 'master' device
% pa_reqlatencyclass = 1; % Try to get the lowest latency that is possible under the constraint of reliable playback.  
% pa_freq = []; %loading default freq for device
% pa_channels = 2; %playing as stereo, converting to mono by hardware connector
% pa_master = PsychPortAudio('Open', cfg.AUDIO_ID, pa_mode, pa_reqlatencyclass, pa_freq, pa_channels);
% 
% % loading audio and verifying output frequency and resampling
% pa_handle_status = PsychPortAudio('GetStatus', pa_master);
% pa_handle_Fs = pa_handle_status.SampleRate;
% onCleanupTasks{18} = onCleanup(@() PsychPortAudio('Close', pa_master));
% 
% % starting master device
% pa_repetitions = 0;
% pa_when = 0;
% pa_waitForStart = 0;
% PsychPortAudio('Start', pa_master, pa_repetitions, pa_when, pa_waitForStart);
% onCleanupTasks{17} = onCleanup(@() PsychPortAudio('Stop', pa_master));

% %% Initialize low-latency microphone
% % Copied and modified from START_SOES_INTRAOP, Latane Bullock 2024 06 03
% 
% 
% % Initialize the recording devices (MRR)
% pa_devices = struct2table(PsychPortAudio('GetDevices'));
% pa_devices_sel = contains(pa_devices.HostAudioAPIName,cfg.MIC_API_NAME) & contains(pa_devices.DeviceName,cfg.MIC_DEVICE); 
% 
% if sum(pa_devices_sel) == 0 
%     disp(pa_devices);
%     error('%s - %s not found. Choose one from the list of available microphone devices',cfg.MIC_API_NAME,cfg.MIC_DEVICE);
% elseif sum(pa_devices_sel) > 1
%     disp(pa_devices);
%     error('%s - %s matches more than one device. Choose one from the list of available microphone devices',cfg.MIC_API_NAME,cfg.MIC_DEVICE);
% else
%     fprintf('The following microphone device was selected');
%     disp(pa_devices(pa_devices_sel,:));
%     cfg.MIC_ID = pa_devices.DeviceIndex(pa_devices_sel);
% end
% 
% recording_device_index = cfg.MIC_ID; 
% % detection_ops.loudness_threshold = cfg.SPEECH_LEVEL_THR; % range 0 to 1
% detection_ops.max_dur_seconds = inf; % don't timeout the detection function
% 
% pa_reqlatencyclass = 1; % set to 1 to not force low latency
% pa_freq = []; % use default frequency
% 
% % recording parameters
% detection_ops.waitscan_seconds = 0.01; % wait this long between recording scans
% suggested_latency_seconds = 0.02; % 'suggestedLatency' to input to PsychPortAudio(‘Open’)
% n_rec_chans = 1; % number of recording channels
% allocated_record_seconds = 1; % 'amountToAllocateSecs' to input to PsychPortAudio(‘GetAudioData’)
% 
% % PsychPortAudio('Close',[]); % close any devices that were left open
% recording_handle = PsychPortAudio('Open', recording_device_index, ...
%     2, pa_reqlatencyclass, pa_freq, n_rec_chans, [], ...
%     suggested_latency_seconds);
% PsychPortAudio('GetAudioData', recording_handle, ...
%     allocated_record_seconds); % initialize recording device with buffer
% 
% detection_ops.recording_repeititions = 0; % loop indefinitely until detection
% detection_ops.recording_when = 0; % start immediately
% 
% cfg.DETECTION_OPS = detection_ops;
% cfg.PA_RECORDER_HANDLE = recording_handle;
% 



%% 

stop_flag = 0; 

while stop_flag~=1

disp('Recording audio for speech detection calibration...'); 

duration = 2; 
% Start audio recording
PsychPortAudio('Start', cfg.PA_RECORDER_HANDLE, 0, 0, 1);
% PsychPortAudio('GetAudioData', pa_master, duration + 1);


% Wait for the specified recording duration
pause(duration);

% Stop recording and retrieve audio data
PsychPortAudio('Stop', cfg.PA_RECORDER_HANDLE);
audioData = PsychPortAudio('GetAudioData', cfg.PA_RECORDER_HANDLE);
PsychPortAudio('Close', cfg.PA_RECORDER_HANDLE);

% Plot the recorded audio data
t = linspace(0, duration, length(audioData));
figure;
plot(t, audioData, 'k');
title('Recorded Audio Waveform');
xlabel('Time (s)');
ylabel('Amplitude');

% Let the user select a time window
disp('Select a time window for analysis by clicking and dragging on the plot.');
% [x, ~] = ginput(2);
hRect = drawrectangle(); 
x = hRect.Position(1) + [0 hRect.Position(3)]; 
% x = sort(x);  % Ensure x(1) is the start and x(2) is the end

% Extract the selected time window
startIndex = find(t >= x(1), 1);
endIndex = find(t <= x(2), 1, 'last');
selectedData = audioData(startIndex:endIndex);

selectedData = abs(selectedData); % take amplitude

% Compute statistics on the selected time window
medianVal = median(selectedData);
lowerQuartile = prctile(selectedData, 25);
upperQuartile = prctile(selectedData, 75);

% Display the statistics
fprintf('Median: %.2f\n', medianVal);
fprintf('Lower Quartile: %.2f\n', lowerQuartile);
fprintf('Upper Quartile: %.2f\n', upperQuartile);

% Prompt the user to save the threshold or try again
saveThreshold = questdlg('Do you want to save this threshold?', 'Save Threshold', 'Yes', 'No, try again', 'Yes');

if strcmp(saveThreshold, 'Yes')

    save(cfg.AUDIO_CALIBRATION_FILENAME, 'medianVal', 'lowerQuartile', 'upperQuartile', 'selectedData', 'audioData');
    fprintf('Threshold saved to %s.\n', cfg.AUDIO_CALIBRATION_FILENAME);
    stop_flag = 1; 

else
    disp('Try recording again.');
end


end


