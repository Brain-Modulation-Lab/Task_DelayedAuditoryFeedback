function daf_engine(cfg)
% DAF_ENGINE - Runs on a dedicated DAF computer, handling real-time audio processing
% and communication with the master control computer via USB serial port.
%
% This function listens for ASCII command strings over USB serial
% (such as START <ms>, STOP, PING, TSYNC, QUIT) and performs delayed audio playback
% based on a dsp.VariableFractionalDelay object, which applies fractional sample delays.
%
% The code assumes USB serial configuration is set in 'cfg' as:
%   cfg.USB_PORT, cfg.USB_BAUDRATE, etc.
%
% Communication protocol:
%  - START <ms>: begins DAF with specified delay in milliseconds.
%  - STOP: halts DAF and clears delay buffer.
%  - PING: engine replies with 'ACK' to confirm liveness.
%  - TSYNC: engine responds with 'ENGINE_T <seconds>' for clock sync.
%  - QUIT: performs cleanup and shuts down the engine.

%% Check for necessary MATLAB and toolboxes
must = @(f) assert(isfield(cfg,f), 'cfg.%s missing', f);
must('AUDIO_DEVICE_IN');
must('AUDIO_DEVICE_OUT');
must('audio_sample_rate');
must('audio_frame_size');
must('maxAllowedDelay_ms');
must('USB_PORT');
must('USB_BAUDRATE');

% Set default gain if not specified
if ~isfield(cfg,'audio_playback_gain')
    cfg.audio_playback_gain = 0.1;
end

% Support lag metrics collection (optional)
if ~isfield(cfg,'LagMetrics') || ~isfield(cfg.LagMetrics,'enable')
    cfg.LagMetrics.enable = false;
end

fs = cfg.audio_sample_rate;             % Sampling rate (Hz)
frameSz = cfg.audio_frame_size;         % Audio buffer frame size
gain = cfg.audio_playback_gain;         % Output volume scaling
maxDelay = cfg.maxAllowedDelay_ms;      % Maximum delay allowed (ms)

% Print configuration info for verification
fprintf('\n[DAF ENGINE]\n  In : %s\n  Out: %s\n  fs : %d  frame: %d\n  USB: %s @ %d\n\n', ...
    cfg.AUDIO_DEVICE_IN, cfg.AUDIO_DEVICE_OUT, fs, frameSz, string(cfg.USB_PORT), cfg.USB_BAUDRATE);

%% Setup audio input/output devices
reader = [];
writer = [];
vfd    = [];
cleanupFns = {};

% Depending on OS, create audioDeviceReader/writer objects with optional driver settings
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
        % macOS / Linux
        reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, ...
            'SampleRate', fs, 'SamplesPerFrame', frameSz);
        writer = audioDeviceWriter('Device', cfg.AUDIO_DEVICE_OUT, ...
            'SampleRate', fs);
    end

    vfd = dsp.VariableFractionalDelay('MaximumDelay', round(fs)); % Instantiate fractional delay object with Furrow interpolation for high-quality delay

    % Prime delay buffer: fill buffer with zero input to avoid initial glitch
    for k = 1:10
        x = reader();
        writer(zeros(frameSz,1));
    end
    cleanupFns{end+1} = onCleanup(@() tryRelease(reader, writer, vfd)); % Register cleanup to release resources on exit
catch ME
    tryRelease(reader, writer, vfd);
    rethrow(ME);
end

%% Setup USB serial port communication with DAF engine via serialport object
try
    sp = serialport(cfg.USB_PORT, cfg.USB_BAUDRATE);  % Create serial port object for command exchange
    configureTerminator(sp, "LF");                    % Use line feed as command termination
    sp.UserData = struct('t0', tic);                  % Store start time for RTT calculations
catch ME
    tryRelease(reader, writer, vfd);
    rethrow(ME);
end
cleanupFns{end+1} = onCleanup(@() tryCloseSerial(sp));              % Register cleanup: close serial port on exit
setappdata(0,'daf_cmd_mailbox', []);                                % Initialize mailbox for communication commands from main control
configureCallback(sp, "terminator", @(h,~) onLine(h, maxDelay));    % Register callback to process incoming serial lines asynchronously
fprintf('[DAF ENGINE] Ready. Waiting for commands...\n');

%% Main processing loop (audio streaming and command execution)
% Supports real-time audio input, fractional delay processing, and command handling
% Loop runs until 'runEngine' flag is set false on 'quit' command

% Initialize state variables
state.isRunning  = false;           % Delay application active flag
state.delay_ms   = 0;               % Current delay in milliseconds
state.delay_samp = 0;               % Current delay in samples
if cfg.LagMetrics.enable
    lagBufN = 5000;                 % Lag data buffer size
    lagBuffer = zeros(1, lagBufN);
    lagIndex = 1;                   % Circular buffer index
    lagCount = 0;                   % Number of collected samples
    framesSinceLog = 0;             % Counter for log updates
end
frame_ms = 1000*frameSz/fs;         % Duration of a thread in milliseconds
runEngine = true;                   % Main loop runs until false

while runEngine
    % Check for serial command queued by callback
    cmd = getappdata(0,'daf_cmd_mailbox');
    if ~isempty(cmd)
        % Process DAF commands: start, stop, quit
        switch cmd.action
            case 'start'
                % Clamp delay value to [0, maxAllowedDelay_ms]
                d_ms = round(cmd.delay_ms);
                d_ms = max(0, min(d_ms, maxDelay));

                % Set delay parameters for processing
                state.delay_ms   = d_ms;
                state.delay_samp = round((state.delay_ms/1000)*fs);

                vfd.reset(); % Reset delay buffer to clear previous delays
                filler = zeros(frameSz, 1);
                for k=1:8
                    vfd(filler, state.delay_samp);  % prime delay buffer
                    writer(filler);
                end

                % Enable delay application
                state.isRunning = true;
                tE = toc(sp.UserData.t0);
                try
                    writeline(sp, sprintf('APPLIED START %d %.6f', state.delay_ms, tE));
                catch
                end
                fprintf('[DAF] START @ %d ms (engine t=%.3f s)\n', state.delay_ms, tE);
            case 'stop'
                % Disable delay application
                state.isRunning = false;
                filler = zeros(frameSz,1); % Flush delay buffer to silence output
                for k = 1:8
                    vfd(filler, state.delay_samp);
                    writer(filler);
                end
                vfd.reset();
                tE = toc(sp.UserData.t0);
                try
                    writeline(sp, sprintf('APPLIED STOP %.6f', tE));
                catch
                end
                fprintf('[DAF] STOP (engine t=%.3f s)\n', tE);
            case 'quit'
                % Shutdown sequence
                state.isRunning = false;
                vfd.reset();
                tE = toc(sp.UserData.t0);
                fprintf('[DAF] QUIT (engine t=%.3f s) — shutting down.\n', tE);
                runEngine = false; % exit main loop
            case 'syncbeep'
                % play a 50 ms 1kHz tone via writer here
                fsLocal = fs;
                N = round(0.05 * fsLocal);
                t = (0:N-1)'/fsLocal;
                beepSig = 0.5 * sin(2*pi*1000*t);
                i = 1;
                while i <= numel(beepSig)
                    idxEnd = min(i+frameSz-1, numel(beepSig));
                    frame  = zeros(frameSz,1);
                    frame(1:(idxEnd-i+1)) = beepSig(i:idxEnd);
                    writer(frame);
                    i = idxEnd + 1;
                end
            otherwise
                % Unknown commands ignored
        end
        setappdata(0,'daf_cmd_mailbox', []); % clear mailbox
    end

    % Acquire audio frame
    if cfg.LagMetrics.enable, tStart = tic; end
    x = reader();
    % Convert multi channel to mono if needed
    if size(x,2) > 1, x = mean(x, 2); end

    % Apply fractional delay if active
    if state.isRunning
        y = vfd(x, state.delay_samp); % Delay processing
        y = max(min(gain*y, 1), -1); % Clip output to [-1, 1]
        writer(y);
    else
        writer(zeros(size(x))); % Output silence
    end

    % Lag metrics collection
    if cfg.LagMetrics.enable
        dt_ms = 1000 * toc(tStart);
        over_ms = max(0, dt_ms - frame_ms);
        lagBuffer(lagIndex) = over_ms;
        lagIndex = mod(lagIndex, lagBufN) + 1;
        lagCount = min(lagCount + 1, lagBufN);
        framesSinceLog = framesSinceLog + 1;
        if framesSinceLog >= round(fs/frameSz)
            framesSinceLog = 0;
            v = lagBuffer(1:lagCount);
            fprintf('[LAG] mean=%.3f ms | max=%.3f ms | n=%d\n', mean(v), max(v), lagCount);
        end
    end
end

% Final lag report
if cfg.LagMetrics.enable && lagCount > 0
    v = lagBuffer(1:lagCount);
    fprintf('[LAG FINAL] mean=%.3f ms | max=%.3f ms | n=%d\n', mean(v), max(v), lagCount);
end

% Cleanup
tryRelease(reader, writer, vfd);
tryCloseSerial(sp);
clear cleanupFns;

end

%% Helpers

% Callback function triggered when a line terminated string is received on the USB serial port
% Parses ASCII command lines sent by the master computer
% Posts corresponding actions to a global mailbox for the main engine process loop to consume asynchronously
function onLine(sp, maxDelay)
    % Read a single line of ASCII command from serial port (terminator = LF)
    line = strtrim(readline(sp));
    if line == ""
        return;
    end

    % Split line into tokens for parsing (command and arguments)
    toks = split(line);
    cmd = upper(string(toks{1}));
    switch cmd
        case "PING"
            % Respond instantly with ACK, no mailbox update needed
            try writeline(sp, "ACK");
            catch
            end

        case "TSYNC"
            % Reply with engine uptime in seconds since engine start
            % This time is used by master for clock offset computation
            if ~isfield(sp.UserData, 't0') || isempty(sp.UserData.t0)
                sp.UserData.t0 = tic; % Initialize start time if missing
            end
            tE = toc(sp.UserData.t0);
            try
                writeline(sp, sprintf('ENGINE_T %.6f', tE));
            catch
            end

        case "START"
            % START command expects one argument <delay_ms>
            if numel(toks) < 2
                fprintf(2,'[DAF] Malformed START (missing ms)\n');
                return;
            end

            % Parse delay value and clamp within valid range
            v = str2double(toks{2});
            if ~isfinite(v) || v < 0 || v > maxDelay
                fprintf(2,'[DAF] START out of range: %s (0..%d)\n', toks{2}, maxDelay); return;
            end
            setappdata(0,'daf_cmd_mailbox', struct('action','start','delay_ms',round(v))); % Post start action with delay to mailbox for engine to apply

        case "STOP"
            % Stop command: inform engine to cease DAF playback
            setappdata(0,'daf_cmd_mailbox', struct('action','stop'));

        case "QUIT"
            % Quit command: shut down engine cleanly
            setappdata(0,'daf_cmd_mailbox', struct('action','quit'));

        case "SYNCBEEP"
            % Generate sync beep tone and play it immediately
            try
                writeline(sp,"ACK");
            catch
            end
            setappdata(0,'daf_cmd_mailbox', struct('action','syncbeep'));

        otherwise
            fprintf(2,'[DAF] Unknown command: %s\n', line);
    end
end

% release audio resources
function tryRelease(reader, writer, vfd)
    try release(reader); catch, end
    try release(writer); catch, end
    try release(vfd); catch, end
end

% close serial port safely
function tryCloseSerial(sp)
    try
        if ~isempty(sp) && isvalid(sp)
            configureCallback(sp,"off");
            delete(sp);
        end
    catch
    end
end