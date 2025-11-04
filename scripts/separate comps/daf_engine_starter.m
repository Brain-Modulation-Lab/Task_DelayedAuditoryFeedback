function daf_engine_starter
% DAF_ENGINE_STARTER - Starter script to launch the delayed auditory feedback (DAF) engine.
%
% This script initializes essential audio and serial interface parameters on the DAF computer
% (the audio playback engine side). It performs device preflight checks for audio hardware,
% sets up USB serial communication parameters, and then launches the main engine loop function daf_engine.m.
%
% This script is intended to be run on the DAF computer only, started after start_daf_intraop_master.m initiates the master side.
%
% No input arguments; all configuration is internal.

%% Configuration of audio and USB parameters
cfg = struct();

% Define audio input/output devices based on operating system
if ispc
    cfg.audio_reader_driver = 'ASIO';
    cfg.audio_writer_driver = 'ASIO';
    cfg.AUDIO_DEVICE_IN     = 'Focusrite USB ASIO';
    cfg.AUDIO_DEVICE_OUT    = 'Focusrite USB ASIO';
elseif ismac
    cfg.AUDIO_DEVICE_IN     = 'MacBook Pro Microphone';
    cfg.AUDIO_DEVICE_OUT    = 'MacBook Pro Speakers';
else
    cfg.AUDIO_DEVICE_IN     = 'Default';
    cfg.AUDIO_DEVICE_OUT    = 'Default';
end

% Core audio settings
cfg.audio_sample_rate   = 44100;   % Audio sampling rate in Hz
cfg.audio_frame_size    = 60;      % Frames per audio buffer process
cfg.maxAllowedDelay_ms  = 1000;    % Maximum allowed audio delay in milliseconds 
cfg.audio_playback_gain = 0.1;     % Digital gain (volume control) for output

% USB serial port used to receive commands from master computer
cfg.USB_PORT     = "COM4";         % Change as needed for your system
cfg.USB_BAUDRATE = 115200;         % Baud rate for communication speed

%% Display configuration banner to console
fprintf('\n[DAF ENGINE STARTER]\n');
fprintf('  Input : %s\n', cfg.AUDIO_DEVICE_IN);
fprintf('  Output: %s\n', cfg.AUDIO_DEVICE_OUT);
fprintf('  USB   : %s @ %d\n\n', string(cfg.USB_PORT), cfg.USB_BAUDRATE);

%% Preflight system checks to ensure proper hardware and files exist
% Check for required DSP System Toolbox for fractional delay processing
if ~exist('dsp.VariableFractionalDelay','class')
    error('DSP System Toolbox required: dsp.VariableFractionalDelay not found.');
end

% Confirm the main engine function file daf_engine.m is on MATLAB path
if ~(exist('daf_engine','file')==2)
    error('daf_engine.m not found on path. Add it, then run daf_engine_starter again.');
end

% Audio device preflight check: try creating and releasing device objects
try
    if ispc
        reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, ...
            'SampleRate', cfg.audio_sample_rate, ...
            'SamplesPerFrame', cfg.audio_frame_size, ...
            'Driver', cfg.audio_reader_driver);

        writer = audioDeviceWriter('Device', cfg.AUDIO_DEVICE_OUT, ...
            'SampleRate', cfg.audio_sample_rate, ...
            'Driver', cfg.audio_writer_driver);
    else
        reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, ...
            'SampleRate', cfg.audio_sample_rate, ...
            'SamplesPerFrame', cfg.audio_frame_size);
        writer = audioDeviceWriter('Device', cfg.AUDIO_DEVICE_OUT, ...
            'SampleRate', cfg.audio_sample_rate);
    end

    % Send a silent frame to validate audio output works
    testFrame = zeros(cfg.audio_frame_size, 1);
    step(writer, testFrame);

    % Release objects after test
    release(reader);
    release(writer);
    fprintf('[Preflight] Audio devices initialized successfully.\n');
catch ME
    error('[Preflight] Audio device setup failed: %s', ME.message);
end

%% Launch the audio processing engine loop
try
    fprintf('[DAF ENGINE STARTER] Launching engine loop...\n');
    daf_engine(cfg);  % Call the main engine function with the configuration
catch ME
    fprintf(2, '[DAF ENGINE STARTER] Engine crashed: %s\n', ME.message);
    rethrow(ME); % Rethrow error for debugging and higher level handling
end

end