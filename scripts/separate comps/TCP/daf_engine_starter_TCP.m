function daf_engine_starter_TCP
% DAF_ENGINE_STARTER (TCP) — engine-side starter on the audio computer

cfg = struct();

% Audio device config
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

cfg.audio_sample_rate   = 44100;
cfg.audio_frame_size    = 60;
cfg.maxAllowedDelay_ms  = 1000;
cfg.audio_playback_gain = 0.1;

% === TCP SERVER SETTINGS ===
cfg.TCP_BIND_ADDR = "0.0.0.0";
cfg.TCP_PORT      = 4444;

fprintf('\n[DAF ENGINE STARTER]\n');
fprintf('  Input : %s\n', cfg.AUDIO_DEVICE_IN);
fprintf('  Output: %s\n', cfg.AUDIO_DEVICE_OUT);
fprintf('  TCP   : %s:%d\n\n', cfg.TCP_BIND_ADDR, cfg.TCP_PORT);

if ~exist('dsp.VariableFractionalDelay','class')
    error('DSP System Toolbox required: dsp.VariableFractionalDelay not found.');
end
if ~(exist('daf_engine','file')==2)
    error('daf_engine.m not found on path. Add it, then run daf_engine_starter again.');
end

% Quick audio preflight
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
    step(writer, zeros(cfg.audio_frame_size,1));
    release(reader); release(writer);
    fprintf('[Preflight] Audio devices initialized successfully.\n');
catch ME
    error('[Preflight] Audio device setup failed: %s', ME.message);
end

% Launch engine loop
try
    fprintf('[DAF ENGINE STARTER] Launching engine loop...\n');
    daf_engine_TCP(cfg);
catch ME
    fprintf(2, '[DAF ENGINE STARTER] Engine crashed: %s\n', ME.message);
    rethrow(ME);
end
end
