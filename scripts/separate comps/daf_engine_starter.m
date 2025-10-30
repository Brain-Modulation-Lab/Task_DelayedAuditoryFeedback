function daf_engine_starter
% DAF Engine Starter (DAF COMPUTER)
% - Minimal config for audio + USB
% - Launches the engine loop that applies delay on command
% - Engine code lives in daf_engine.m

cfg = struct();

% ---------- AUDIO DEVICES ON DAF BOX ----------
% Set these to the DAF machine's actual devices
if ispc
    cfg.audio_reader_driver = 'ASIO';       % 'ASIO'|'WASAPI'|'DirectSound' as appropriate
    cfg.audio_writer_driver = 'ASIO';
    cfg.AUDIO_DEVICE_IN     = 'Focusrite USB ASIO';
    cfg.AUDIO_DEVICE_OUT    = 'Focusrite USB ASIO';
elseif ismac
    cfg.AUDIO_DEVICE_IN     = 'MacBook Pro Microphone';
    cfg.AUDIO_DEVICE_OUT    = 'MacBook Pro Speakers';
    % CoreAudio doesn't need driver fields
else
    cfg.AUDIO_DEVICE_IN     = 'Default';
    cfg.AUDIO_DEVICE_OUT    = 'Default';
end

cfg.audio_sample_rate   = 44100;
cfg.audio_frame_size    = 60;      % keep small for low latency
cfg.maxAllowedDelay_ms  = 1000;
cfg.audio_playback_gain = 0.1;     % engine may clip-protect anyway

% ---------- USB-Serial from MASTER ----------
cfg.USB_PORT    = "COM4";          % <-- set to the DAF box's port connected to MASTER
cfg.USB_BAUDRATE= 115200;

% ---------- Banner ----------
fprintf('\n[DAF ENGINE STARTER]\n');
fprintf('  Input : %s\n', cfg.AUDIO_DEVICE_IN);
fprintf('  Output: %s\n', cfg.AUDIO_DEVICE_OUT);
fprintf('  USB   : %s @ %d\n\n', string(cfg.USB_PORT), cfg.USB_BAUDRATE);

% ---------- Launch engine loop ----------
if ~(exist('daf_engine','file')==2)
    error('daf_engine.m not found on path. Add it, then run daf_engine_starter again.');
end
daf_engine(cfg);   % runs until you close it (CTRL-C or engine STOP logic)
end