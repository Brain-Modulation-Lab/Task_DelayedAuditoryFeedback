function daf_engine(cfg)
% DAF ENGINE (run on the dedicated DAF computer)
% Listens on USB-serial for:  START <ms> | SET <ms> | STOP | PING | QUIT
% Applies mic->delay->speaker using dsp.VariableFractionalDelay.
%
% Required cfg fields (set by daf_engine_starter.m):
%   cfg.AUDIO_DEVICE_IN, cfg.AUDIO_DEVICE_OUT
%   cfg.audio_sample_rate, cfg.audio_frame_size
%   [optional] cfg.audio_reader_driver, cfg.audio_writer_driver (Windows)
%   cfg.maxAllowedDelay_ms
%   cfg.audio_playback_gain
%   cfg.USB_PORT, cfg.USB_BAUDRATE
%
% Protocol (ASCII, newline-terminated):
%   START <ms>   begin delayed playback at <ms>
%   SET   <ms>   update delay while running
%   STOP         stop delayed playback (output silence)
%   PING         engine replies 'ACK'
%   QUIT         graceful shutdown of engine
%
% Notes:
% - No Psychtoolbox dependency (uses tic/toc instead of GetSecs).
% - On STOP we hard-reset the delay line (cut audio immediately).
% - On START/SET, delay is clamped to [0, maxAllowedDelay_ms].

%% -------- Defaults & guards --------
must = @(f) assert(isfield(cfg,f), 'cfg.%s missing', f);
must('AUDIO_DEVICE_IN'); must('AUDIO_DEVICE_OUT');
must('audio_sample_rate'); must('audio_frame_size');
must('maxAllowedDelay_ms'); must('USB_PORT'); must('USB_BAUDRATE');

if ~isfield(cfg,'audio_playback_gain'), cfg.audio_playback_gain = 0.1; end

fs       = cfg.audio_sample_rate;
frameSz  = cfg.audio_frame_size;
gain     = cfg.audio_playback_gain;
maxDelay = cfg.maxAllowedDelay_ms;

fprintf('\n[DAF ENGINE]\n  In : %s\n  Out: %s\n  fs : %d  frame: %d\n  USB: %s @ %d\n\n', ...
    cfg.AUDIO_DEVICE_IN, cfg.AUDIO_DEVICE_OUT, fs, frameSz, string(cfg.USB_PORT), cfg.USB_BAUDRATE);

%% -------- Audio I/O --------
reader = [];
writer = [];
vfd    = [];
cleanupFns = {};

try
    if ispc
        if isfield(cfg,'audio_reader_driver')
            reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, ...
                'SampleRate', fs, 'SamplesPerFrame', frameSz, 'Driver', cfg.audio_reader_driver);
        else
            reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, ...
                'SampleRate', fs, 'SamplesPerFrame', frameSz);
        end
        if isfield(cfg,'audio_writer_driver')
            writer = audioDeviceWriter('Device', cfg.AUDIO_DEVICE_OUT, ...
                'SampleRate', fs, 'Driver', cfg.audio_writer_driver);
        else
            writer = audioDeviceWriter('Device', cfg.AUDIO_DEVICE_OUT, ...
                'SampleRate', fs);
        end
    else
        % macOS / Linux (CoreAudio/ALSA typically don't need explicit driver arg)
        reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, ...
            'SampleRate', fs, 'SamplesPerFrame', frameSz);
        writer = audioDeviceWriter('Device', cfg.AUDIO_DEVICE_OUT, ...
            'SampleRate', fs);
    end

    % Delay line (max 1 second at fs)
    vfd = dsp.VariableFractionalDelay('MaximumDelay', round(fs));
    % Prime the path to avoid first-block glitch
    for k = 1:10
        x = reader(); %#ok<NASGU> % discard
        writer(zeros(frameSz,1));
    end

    cleanupFns{end+1} = onCleanup(@() tryRelease(reader, writer, vfd));
catch ME
    tryRelease(reader, writer, vfd);
    rethrow(ME);
end

%% -------- USB-Serial (newline protocol) --------
try
    sp = serialport(cfg.USB_PORT, cfg.USB_BAUDRATE);
    configureTerminator(sp, "LF");
catch ME
    tryRelease(reader, writer, vfd);
    rethrow(ME);
end
cleanupFns{end+1} = onCleanup(@() tryCloseSerial(sp));

% Use a simple mailbox for commands posted by the callback
setappdata(0,'daf_cmd_mailbox', []);
configureCallback(sp, "terminator", @(h,~) onLine(h, maxDelay));

fprintf('[DAF ENGINE] Ready. Waiting for commands...\n');

%% -------- Engine state & main loop --------
state.isRunning  = false;
state.delay_ms   = 0;
state.delay_samp = 0;

% Lightweight diagnostics
frame_ms = 1000*frameSz/fs;
lagBuf   = zeros(1, 4096); lagN = 0;

tStartLoop = tic;
runEngine  = true;

while runEngine
    % 1) Drain mailbox (apply latest command ASAP)
    cmd = getappdata(0,'daf_cmd_mailbox');
    if ~isempty(cmd)
        switch cmd.action
            case 'start'
                state.delay_ms   = cmd.delay_ms;
                state.delay_samp = fs * cmd.delay_ms / 1000;
                state.isRunning  = true;
                fprintf('[DAF] START  @ %d ms\n', state.delay_ms);

            case 'set'
                state.delay_ms   = cmd.delay_ms;
                state.delay_samp = fs * cmd.delay_ms / 1000;
                if state.isRunning
                    fprintf('[DAF] SET    -> %d ms\n', state.delay_ms);
                else
                    fprintf('[DAF] SET (armed) %d ms\n', state.delay_ms);
                end

            case 'stop'
                state.isRunning  = false;
                vfd.reset();
                fprintf('[DAF] STOP\n');

            case 'quit'
                state.isRunning  = false;
                vfd.reset();
                fprintf('[DAF] QUIT received. Shutting down.\n');
                runEngine = false;

            case 'ping'
                % no state change
            
            case "TSYNC"
                % NTP-like 1-shot: master sends TSYNC; engine replies ENGINE_T <tE>
                % where <tE> is engine time in seconds since engine start.
                tE = toc(tStartLoop);              % engine monotonic time (define tStartLoop at engine start)
                try writeline(sp, sprintf("ENGINE_T %.6f", tE)); catch, end
        end
        % clear mailbox
        setappdata(0,'daf_cmd_mailbox', []);
    end

    % 2) Process one audio frame
    t0 = tic;
    x  = reader();               % column vector (mono) expected
    if state.isRunning
        y = vfd(x, state.delay_samp);
        % clip protect and gain
        y = max(min(gain*y, 1), -1);
        writer(y);
    else
        % mute while idle
        writer(zeros(size(x)));
    end

    % 3) Soft processing-lag metric (optional console)
    dt = 1000*toc(t0) - frame_ms;
    if dt < 0, dt = 0; end
    lagN = lagN + 1;
    if lagN <= numel(lagBuf), lagBuf(lagN) = dt; end

    % Yield a hair to OS
    pause(0.0005);
end

% Print a tiny lag summary (best-effort)
if lagN > 0
    mLag = mean(lagBuf(1:min(lagN,numel(lagBuf))));
    fprintf('[DAF] Avg processing lag: %.2f ms\n', mLag);
end

% Cleanup (onCleanup handles will fire too)
tryRelease(reader, writer, vfd);
tryCloseSerial(sp);
clear cleanupFns;

end % function daf_engine

%% ======== Helpers ========

function onLine(sp, maxDelay)
% Parse one ASCII line from serial; post to mailbox; respond to PING.
line = strtrim(readline(sp));
if line == ""
    return
end
toks = split(line);
cmd  = upper(string(toks{1}));

switch cmd
    case "PING"
        try writeline(sp, "ACK"); catch, end
        % also drop a 'ping' action for bookkeeping if needed
        setappdata(0,'daf_cmd_mailbox', struct('action','ping'));

    case {"START","SET"}
        if numel(toks) < 2
            fprintf(2,'[DAF] Malformed %s (missing ms)\n', cmd); return
        end
        v = str2double(toks{2});
        if ~isfinite(v) || v < 0 || v > maxDelay
            fprintf(2,'[DAF] %s out of range: %s (0..%d)\n', cmd, toks{2}, maxDelay); return
        end
        act = lower(cmd); % 'start' or 'set'
        setappdata(0,'daf_cmd_mailbox', struct('action',act,'delay_ms',round(v)));

    case "STOP"
        setappdata(0,'daf_cmd_mailbox', struct('action','stop'));

    case "QUIT"
        setappdata(0,'daf_cmd_mailbox', struct('action','quit'));

    otherwise
        fprintf(2,'[DAF] Unknown command: %s\n', line);
end
end

function tryRelease(reader, writer, vfd)
try release(reader); catch, end
try release(writer); catch, end
try release(vfd);    catch, end
end

function tryCloseSerial(sp)
try
    if ~isempty(sp) && isvalid(sp)
        configureCallback(sp, "off");
        clear sp; % close handle
    end
catch
end
end