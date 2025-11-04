function daf_engine_TCP(cfg)
% DAF_ENGINE (TCP) — audio engine with TCP command channel (robust Windows I/O)

% ===== Required fields =====
must = @(f) assert(isfield(cfg,f), 'cfg.%s missing', f);
must('AUDIO_DEVICE_IN'); must('AUDIO_DEVICE_OUT');
must('audio_sample_rate'); must('audio_frame_size');
must('maxAllowedDelay_ms');

% ===== Optional fields / defaults =====
if ~isfield(cfg,'TCP_PORT'),          cfg.TCP_PORT = 4444; end
if ~isfield(cfg,'TCP_BIND_ADDR'),     cfg.TCP_BIND_ADDR = "0.0.0.0"; end
if ~isfield(cfg,'audio_playback_gain'), cfg.audio_playback_gain = 0.1; end
if ~isfield(cfg,'LagMetrics') || ~isfield(cfg.LagMetrics,'enable')
    cfg.LagMetrics = struct('enable', false);
end
if ~isfield(cfg,'debug_passthrough'), cfg.debug_passthrough = false; end     % true = bypass delay (for quick I/O check)
if ~isfield(cfg,'print_input_rms'),   cfg.print_input_rms   = true;  end     % print RMS once/sec
if ~isfield(cfg,'input_channel'),     cfg.input_channel     = 1;     end     % use only ch# (1-based), 0 = mixdown to mono
if ~isfield(cfg,'audio_reader_driver'), cfg.audio_reader_driver = ''; end     % '', 'ASIO', 'wasapi'
if ~isfield(cfg,'audio_writer_driver'), cfg.audio_writer_driver = ''; end     % '', 'ASIO', 'wasapi'

% ===== Local copies =====
fs       = cfg.audio_sample_rate;
frameSz  = cfg.audio_frame_size;
gain     = cfg.audio_playback_gain;
maxDelay = cfg.maxAllowedDelay_ms;

fprintf('\n[DAF ENGINE]\n  In : %s\n  Out: %s\n  fs : %d  frame: %d\n  TCP: %s:%d\n', ...
    cfg.AUDIO_DEVICE_IN, cfg.AUDIO_DEVICE_OUT, fs, frameSz, string(cfg.TCP_BIND_ADDR), cfg.TCP_PORT);
if ~isempty(cfg.audio_reader_driver) || ~isempty(cfg.audio_writer_driver)
    fprintf('  Drivers → reader:%s  writer:%s\n', blankIfEmpty(cfg.audio_reader_driver), blankIfEmpty(cfg.audio_writer_driver));
end
fprintf('\n');

% ===== Audio I/O (robust Windows handling) =====
reader = []; writer = []; vfd = [];
createdWith = struct('reader','', 'writer','');

% Try to create READER with requested driver → fallback to WASAPI → fallback to default
try
    reader = createReader(cfg.AUDIO_DEVICE_IN, fs, frameSz, cfg.audio_reader_driver);
    createdWith.reader = reader.Driver;
catch ME1
    warning('[AudioReader] Failed (%s). Trying WASAPI…', message);
    try
        reader = createReader(cfg.AUDIO_DEVICE_IN, fs, frameSz, 'wasapi');
        createdWith.reader = reader.Driver;
    catch ME2
        warning('[AudioReader] WASAPI failed (%s). Trying default driver…', message);
        reader = createReader(cfg.AUDIO_DEVICE_IN, fs, frameSz, '');
        createdWith.reader = reader.Driver;
    end
end

% Try to create WRITER with requested driver → fallback to WASAPI → fallback to default
try
    writer = createWriter(cfg.AUDIO_DEVICE_OUT, fs, cfg.audio_writer_driver);
    createdWith.writer = writer.Driver;
catch ME1
    warning('[AudioWriter] Failed (%s). Trying WASAPI…', message);
    try
        writer = createWriter(cfg.AUDIO_DEVICE_OUT, fs, 'wasapi');
        createdWith.writer = writer.Driver;
    catch ME2
        warning('[AudioWriter] WASAPI failed (%s). Trying default driver…', message);
        writer = createWriter(cfg.AUDIO_DEVICE_OUT, fs, '');
        createdWith.writer = writer.Driver;
    end
end

fprintf('[Audio] Reader: %s (%s)  |  Writer: %s (%s)\n', ...
    reader.Device, reader.Driver, writer.Device, writer.Driver);

% If device rejected fs, reader.SampleRate will differ or throw. Sanity check:
if reader.SampleRate ~= fs
    warning('[Audio] Reader requested fs=%d but reports %d. Adjusting engine fs to match device.', fs, reader.SampleRate);
    fs = reader.SampleRate;
end
if writer.SampleRate ~= fs
    warning('[Audio] Writer requested fs=%d but reports %d. Adjusting writer to reader fs=%d.', cfg.audio_sample_rate, writer.SampleRate, fs);
    % Recreate writer at reader fs
    release(writer);
    writer = createWriter(cfg.AUDIO_DEVICE_OUT, fs, createdWith.writer);
end

% VariableFractionalDelay with generous bound (ms→samples) + headroom
maxSamp = ceil((maxDelay/1000)*fs) + fs; % +1s cushion
vfd = dsp.VariableFractionalDelay('MaximumDelay', max(maxSamp, fs));

% Prime the path (pull input; keep output quiet)
for k = 1:10
    x = reader();
    %#ok<NASGU>
    stepSilent(writer, zeros(frameSz,1));
end

% ===== TCP server =====
try
    srv = tcpserver(cfg.TCP_BIND_ADDR, cfg.TCP_PORT, 'ConnectionChangedFcn', @onConnChanged);
    configureCallback(srv, "byte", 1, @(h,~) onTcpBytes(h, maxDelay));
    srv.UserData = struct('t0', tic, 'rxbuf', uint8([]), 'mailbox', []);
catch ME
    tryRelease(reader, writer, vfd);
    rethrow(ME);
end
cleanupTCP = onCleanup(@() tryCloseServer(srv));

fprintf('[DAF ENGINE] Ready. Waiting for commands…\n');

% ===== State & loop =====
state.isRunning  = false;
state.delay_ms   = 0;
state.delay_samp = 0;

if cfg.LagMetrics.enable
    lagBufN=5000; lagBuffer=zeros(1,lagBufN); lagIndex=1; lagCount=0; framesSinceLog=0;
end
frame_ms = 1000*frameSz/fs;
runEngine = true;

% RMS debug helper
tPrint = tic;

while runEngine
    % Consume mailbox
    mb = srv.UserData.mailbox;
    if ~isempty(mb)
        switch mb.action
            case 'start'
                d_ms = clamp(round(mb.delay_ms), 0, maxDelay);
                state.delay_ms   = d_ms;
                state.delay_samp = (state.delay_ms/1000)*fs;   % keep fractional precise
                reset(vfd);
                filler = zeros(frameSz,1);
                % prefill writer with a few silent frames so the delay line can build
                for k=1:8
                    stepSilent(writer, filler);
                end
                state.isRunning = true;
                tE = toc(srv.UserData.t0);
                safeTcpWriteLine(srv, sprintf('APPLIED START %d %.6f', state.delay_ms, tE));
                fprintf('[DAF] START @ %d ms (engine t=%.3f s)\n', state.delay_ms, tE);

            case 'stop'
                state.isRunning = false;
                filler = zeros(frameSz,1);
                % drain with silence a bit to flush path
                for k=1:8
                    stepSilent(writer, filler);
                end
                reset(vfd);
                tE = toc(srv.UserData.t0);
                safeTcpWriteLine(srv, sprintf('APPLIED STOP %.6f', tE));
                fprintf('[DAF] STOP (engine t=%.3f s)\n', tE);

            case 'quit'
                state.isRunning = false;
                reset(vfd);
                tE = toc(srv.UserData.t0);
                fprintf('[DAF] QUIT (engine t=%.3f s) — shutting down.\n', tE);
                runEngine = false;

            case 'syncbeep'
                % 50 ms / 1 kHz tone
                N = round(0.05*fs);
                t = (0:N-1)'/fs;
                beepSig = 0.5*sin(2*pi*1000*t);
                pushStream(writer, beepSig, frameSz);
        end
        % clear mailbox
        ud = srv.UserData; ud.mailbox = []; srv.UserData = ud;
    end

    % Acquire input
    if cfg.LagMetrics.enable, tStart=tic; end
    x = reader();
    if isempty(x), x = zeros(frameSz,1); end

    % Channel handling → either pick one channel or mixdown to mono
    if size(x,2) > 1
        if cfg.input_channel > 0 && cfg.input_channel <= size(x,2)
            x = x(:, cfg.input_channel);
        else
            x = mean(x,2);
        end
    end

    % Optional RMS prints (debug if mic is actually live)
    if cfg.print_input_rms && toc(tPrint) > 1
        fprintf('[IN] RMS=%.4f  isRunning=%d  delay=%.1f ms  fs=%d\n', ...
            rmsFast(x), state.isRunning, state.delay_ms, fs);
        tPrint = tic;
    end

    % Process / write
    if cfg.debug_passthrough
        y = x;                   % bypass (debug)
    elseif state.isRunning
        y = vfd(x, state.delay_samp);
    else
        y = zeros(size(x));      % silence when not running
    end
    % scale & clip
    y = clip1(gain * y);
    stepSilent(writer, y);

    % Lag metrics
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

    pause(0.0005);
end

% Final lag report
if cfg.LagMetrics.enable && exist('lagCount','var') && lagCount > 0
    v = lagBuffer(1:lagCount);
    fprintf('[LAG FINAL] mean=%.3f ms | max=%.3f ms | n=%d\n', mean(v), max(v), lagCount);
end

tryRelease(reader, writer, vfd);
tryCloseServer(srv);
end

%% ===== Helpers ===========================================================
function r = createReader(device, fs, spf, driver)
    args = {'Device', device, 'SampleRate', fs, 'SamplesPerFrame', spf};
    if ~isempty(driver), args = [args {'Driver', driver}]; end
    r = audioDeviceReader(args{:});
end

function w = createWriter(device, fs, driver)
    args = {'Device', device, 'SampleRate', fs};
    if ~isempty(driver), args = [args {'Driver', driver}]; end
    w = audioDeviceWriter(args{:});
end

function onConnChanged(srv, ~)
    if srv.Connected
        fprintf('[TCP] Client connected: %s:%d\n', srv.ClientAddress, srv.ClientPort);
    else
        fprintf('[TCP] Client disconnected.\n');
    end
end

function onTcpBytes(srv, maxDelay)
    ud  = srv.UserData;
    buf = [ud.rxbuf read(srv, srv.NumBytesAvailable, 'uint8')];
    [lines, leftover] = splitLines(buf);
    ud.rxbuf = leftover;
    srv.UserData = ud;

    for i = 1:numel(lines)
        L = strtrim(lines{i});
        if L == "", continue; end
        toks = split(L); cmd = upper(string(toks{1}));
        switch cmd
            case "PING"
                safeTcpWriteLine(srv, "ACK");
            case "TSYNC"
                if ~isfield(ud,'t0') || isempty(ud.t0), ud.t0 = tic; end
                tE = toc(ud.t0); srv.UserData = ud;
                safeTcpWriteLine(srv, sprintf('ENGINE_T %.6f', tE));
            case "START"
                if numel(toks) < 2, fprintf(2,'[DAF] Malformed START\n'); continue; end
                v = str2double(toks{2});
                if ~isfinite(v) || v < 0 || v > maxDelay
                    fprintf(2,'[DAF] START out of range: %s (0..%d)\n', toks{2}, maxDelay); continue;
                end
                postMailbox(srv, 'start', round(v));
            case "STOP"
                postMailbox(srv, 'stop');
            case "QUIT"
                postMailbox(srv, 'quit');
            case "SYNCBEEP"
                safeTcpWriteLine(srv, "ACK");
                postMailbox(srv, 'syncbeep');
            otherwise
                fprintf(2,'[DAF] Unknown cmd: %s\n', L);
        end
    end
end

function postMailbox(srv, action, delay_ms)
    ud = srv.UserData;
    if nargin < 3
        ud.mailbox = struct('action', action);
    else
        ud.mailbox = struct('action', action, 'delay_ms', delay_ms);
    end
    srv.UserData = ud;
end

function safeTcpWriteLine(srv, s)
    try
        write(srv, uint8([char(s) 10])); % append '\n'
    catch
    end
end

function [lines, leftover] = splitLines(data)
    if isempty(data), lines = {}; leftover = data; return; end
    nl = find(data == 10);
    if isempty(nl), lines = {}; leftover = data; return; end
    cut = nl(end);
    chunks = mat2cell(data(1:cut-1), 1, diff([0 nl(:)'-1]));
    chunks = chunks(~cellfun(@isempty, chunks));
    lines  = cellfun(@(u) char(u), chunks, 'UniformOutput', false);
    leftover = data(cut+1:end);
end

function tryCloseServer(srv)
    try
        if ~isempty(srv)
            configureCallback(srv, "off");
            clear srv;
        end
    catch
    end
end

function tryRelease(reader, writer, vfd)
    try release(reader); catch, end
    try release(writer); catch, end
    try release(vfd);    catch, end
end

function y = clip1(x)
    y = min(max(x, -1), 1);
end

function stepSilent(w, frame)
    try
        w(frame);
    catch
        % swallow sporadic glitches
    end
end

function pushStream(w, sig, frameSz)
    i = 1;
    N = numel(sig);
    while i <= N
        idxEnd = min(i + frameSz - 1, N);
        f = zeros(frameSz,1);
        f(1:(idxEnd - i + 1)) = sig(i:idxEnd);
        stepSilent(w, f);
        i = idxEnd + 1;
    end
end

function v = rmsFast(x)
    v = sqrt(mean(x.^2));
end

function v = clamp(x, a, b)
    v = min(max(x,a), b);
end

function s = blankIfEmpty(x)
    if isempty(x), s = '(default)'; else, s = x; end
end
