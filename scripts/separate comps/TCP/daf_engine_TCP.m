function daf_engine_TCP(cfg)
% DAF_ENGINE (TCP) — audio engine with TCP command channel

must = @(f) assert(isfield(cfg,f), 'cfg.%s missing', f);
must('AUDIO_DEVICE_IN'); must('AUDIO_DEVICE_OUT');
must('audio_sample_rate'); must('audio_frame_size');
must('maxAllowedDelay_ms');
if ~isfield(cfg,'TCP_PORT'), cfg.TCP_PORT = 4444; end
if ~isfield(cfg,'TCP_BIND_ADDR'), cfg.TCP_BIND_ADDR = "0.0.0.0"; end
if ~isfield(cfg,'audio_playback_gain'), cfg.audio_playback_gain = 0.1; end
if ~isfield(cfg,'LagMetrics') || ~isfield(cfg.LagMetrics,'enable')
    cfg.LagMetrics.enable = false;
end

fs = cfg.audio_sample_rate;
frameSz = cfg.audio_frame_size;
gain = cfg.audio_playback_gain;
maxDelay = cfg.maxAllowedDelay_ms;

fprintf('\n[DAF ENGINE]\n  In : %s\n  Out: %s\n  fs : %d  frame: %d\n  TCP: %s:%d\n\n', ...
    cfg.AUDIO_DEVICE_IN, cfg.AUDIO_DEVICE_OUT, fs, frameSz, string(cfg.TCP_BIND_ADDR), cfg.TCP_PORT);

% Audio devices
reader = []; writer=[]; vfd=[];
try
    if ispc
        if isfield(cfg,'audio_reader_driver')
            reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, 'SampleRate', fs, 'SamplesPerFrame', frameSz, 'Driver', cfg.audio_reader_driver);
        else
            reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, 'SampleRate', fs, 'SamplesPerFrame', frameSz);
        end
        if isfield(cfg,'audio_writer_driver')
            writer = audioDeviceWriter('Device', cfg.AUDIO_DEVICE_OUT, 'SampleRate', fs, 'Driver', cfg.audio_writer_driver);
        else
            writer = audioDeviceWriter('Device', cfg.AUDIO_DEVICE_OUT, 'SampleRate', fs);
        end
    else
        reader = audioDeviceReader('Device', cfg.AUDIO_DEVICE_IN, 'SampleRate', fs, 'SamplesPerFrame', frameSz);
        writer = audioDeviceWriter('Device', cfg.AUDIO_DEVICE_OUT, 'SampleRate', fs);
    end
    vfd = dsp.VariableFractionalDelay('MaximumDelay', round(fs)); % Farrow filter
    % Prime I/O path
    for k=1:10, x = reader(); %#ok<NASGU>
        writer(zeros(frameSz,1));
    end
catch ME
    tryRelease(reader, writer, vfd);
    rethrow(ME);
end

% TCP server
try
    srv = tcpserver(cfg.TCP_BIND_ADDR, cfg.TCP_PORT, 'ConnectionChangedFcn', @onConnChanged);
    % We'll process bytes in a callback:
    configureCallback(srv, "byte", 1, @(h,~) onTcpBytes(h, maxDelay));
    srv.UserData = struct('t0', tic, 'rxbuf', uint8([]), 'mailbox', []);
catch ME
    tryRelease(reader, writer, vfd);
    rethrow(ME);
end
cleanup = onCleanup(@() tryCloseServer(srv));

fprintf('[DAF ENGINE] Ready. Waiting for commands...\n');

% State / main loop
state.isRunning = false;
state.delay_ms  = 0;
state.delay_samp= 0;

if cfg.LagMetrics.enable
    lagBufN=5000; lagBuffer=zeros(1,lagBufN); lagIndex=1; lagCount=0; framesSinceLog=0;
end
frame_ms = 1000*frameSz/fs;
runEngine = true;

while runEngine
    % Consume mailbox
    mb = srv.UserData.mailbox;
    if ~isempty(mb)
        switch mb.action
            case 'start'
                d_ms = round(mb.delay_ms);
                d_ms = max(0, min(d_ms, maxDelay));
                state.delay_ms = d_ms;
                state.delay_samp = round((state.delay_ms/1000)*fs); % allow integer-sample delay; flip to fractional if desired
                vfd.reset();
                filler=zeros(frameSz,1);
                for k=1:8
                    vfd(filler, state.delay_samp);
                    writer(filler);
                end
                state.isRunning=true;
                tE = toc(srv.UserData.t0);
                try tcpWriteLine(srv, sprintf('APPLIED START %d %.6f', state.delay_ms, tE)); catch, end
                fprintf('[DAF] START @ %d ms (engine t=%.3f s)\n', state.delay_ms, tE);
            case 'stop'
                state.isRunning=false;
                filler=zeros(frameSz,1);
                for k=1:8
                    vfd(filler, state.delay_samp);
                    writer(filler);
                end
                vfd.reset();
                tE = toc(srv.UserData.t0);
                try tcpWriteLine(srv, sprintf('APPLIED STOP %.6f', tE)); catch, end
                fprintf('[DAF] STOP (engine t=%.3f s)\n', tE);
            case 'quit'
                state.isRunning=false;
                vfd.reset();
                tE = toc(srv.UserData.t0);
                fprintf('[DAF] QUIT (engine t=%.3f s) — shutting down.\n', tE);
                runEngine=false;
            case 'syncbeep'
                % 50 ms 1kHz
                N = round(0.05*fs);
                t = (0:N-1)'/fs;
                beepSig = 0.5*sin(2*pi*1000*t);
                i=1;
                while i<=numel(beepSig)
                    idxEnd=min(i+frameSz-1, numel(beepSig));
                    frame=zeros(frameSz,1);
                    frame(1:(idxEnd-i+1)) = beepSig(i:idxEnd);
                    writer(frame);
                    i=idxEnd+1;
                end
            otherwise
        end
        % clear mailbox
        ud = srv.UserData; ud.mailbox = []; srv.UserData = ud;
    end

    % Audio streaming
    if cfg.LagMetrics.enable, tStart=tic; end
    x = reader(); if size(x,2)>1, x=mean(x,2); end
    if state.isRunning
        y = vfd(x, state.delay_samp);
        y = max(min(gain*y,1), -1);
        writer(y);
    else
        writer(zeros(size(x)));
    end

    % Lag metrics
    if cfg.LagMetrics.enable
        dt_ms = 1000*toc(tStart);
        over_ms = max(0, dt_ms - frame_ms);
        lagBuffer(lagIndex)=over_ms;
        lagIndex = mod(lagIndex, lagBufN)+1;
        lagCount = min(lagCount+1, lagBufN);
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
if exist('lagCount','var') && lagCount>0
    v = lagBuffer(1:lagCount);
    fprintf('[LAG FINAL] mean=%.3f ms | max=%.3f ms | n=%d\n', mean(v), max(v), lagCount);
end

tryRelease(reader, writer, vfd);
tryCloseServer(srv);
end

%% === TCP helpers ===
function onConnChanged(srv, ~)
% just a notice; nothing required here unless you want logs
if srv.Connected
    fprintf('[TCP] Client connected: %s:%d\n', srv.ClientAddress, srv.ClientPort);
else
    fprintf('[TCP] Client disconnected.\n');
end
end

function onTcpBytes(srv, maxDelay)
% accumulate into rxbuf, split on '\n', handle lines
ud = srv.UserData;
buf = [ud.rxbuf read(srv, srv.NumBytesAvailable, 'uint8')];
[lines, leftover] = splitLines(buf);
ud.rxbuf = leftover;
srv.UserData = ud;

for i=1:numel(lines)
    L = strtrim(lines{i});
    if L=="", continue; end
    toks = split(L); cmd = upper(string(toks{1}));
    switch cmd
        case "PING"
            try tcpWriteLine(srv, "ACK"); catch, end
        case "TSYNC"
            if ~isfield(ud,'t0') || isempty(ud.t0), ud.t0 = tic; end
            tE = toc(ud.t0); srv.UserData = ud;
            try tcpWriteLine(srv, sprintf('ENGINE_T %.6f', tE)); catch, end
        case "START"
            if numel(toks)<2, fprintf(2,'[DAF] Malformed START\n'); continue; end
            v = str2double(toks{2});
            if ~isfinite(v) || v<0 || v>maxDelay
                fprintf(2,'[DAF] START out of range: %s (0..%d)\n', toks{2}, maxDelay); continue;
            end
            postMailbox(srv,'start',round(v));
        case "STOP"
            postMailbox(srv,'stop');
        case "QUIT"
            postMailbox(srv,'quit');
        case "SYNCBEEP"
            try tcpWriteLine(srv, "ACK"); catch, end
            postMailbox(srv,'syncbeep');
        otherwise
            fprintf(2,'[DAF] Unknown cmd: %s\n', L);
    end
end
end

function postMailbox(srv, action, delay_ms)
ud = srv.UserData;
if nargin<3, ud.mailbox = struct('action',action);
else, ud.mailbox = struct('action',action,'delay_ms',delay_ms);
end
srv.UserData = ud;
end

function tcpWriteLine(srv, s)
write(srv, uint8([char(s) 10])); % append '\n'
end

function [lines, leftover] = splitLines(data)
if isempty(data), lines={}; leftover=data; return; end
nl = find(data==10);
if isempty(nl), lines={}; leftover=data; return; end
cut = nl(end);
chunks = mat2cell(data(1:cut-1), 1, diff([0 nl(:)'-1]));
keep = ~cellfun(@isempty, chunks);
chunks = chunks(keep);
lines = cellfun(@(u) char(u), chunks, 'UniformOutput', false);
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
