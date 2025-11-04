function task_daf_master_TCP(cfg)
% TASK_DAF_MASTER (TCP transport)

%% Validate config & defaults (same as before)
if ~isfield(cfg,'PATH_TASK') || ~isfolder(cfg.PATH_TASK), error('cfg.PATH_TASK missing/invalid'); end
if ~isfield(cfg,'EVENT_FILENAME') || ~isfield(cfg,'TRIAL_FILENAME'), error('cfg EVENT/TRIAL filenames missing'); end
if ~isfield(cfg,'NET_ACK_TIMEOUT_S'), cfg.NET_ACK_TIMEOUT_S = 0.10; end
if ~isfield(cfg,'NET_MAX_RETRIES'),   cfg.NET_MAX_RETRIES   = 0;    end
if ~isfield(cfg,'DAF_START_OFFSET_S'),cfg.DAF_START_OFFSET_S= 0;    end
if ~isfield(cfg,'text_stim_dur'),     cfg.text_stim_dur     = 10;   end
if ~isfield(cfg,'n_blocks'),          cfg.n_blocks          = 1;    end

%% Timing backend (unchanged)
usePTB = false;
if isfield(cfg,'PTB')
    if islogical(cfg.PTB), usePTB = cfg.PTB;
    elseif ischar(cfg.PTB) || isstring(cfg.PTB)
        usePTB = any(strcmpi(string(cfg.PTB), ["true","on","ptb","1"]));
    end
end
if usePTB && exist('GetSecs','file')>0 && exist('WaitSecs','file')>0
    T.now   = @GetSecs;
    T.wait  = @(s) WaitSecs(max(0,s));
    T.until = @(t) WaitSecs('UntilTime', t);
    T.backend = 'PTB';
else
    t0 = tic;
    T.now   = @() toc(t0);
    T.wait  = @(s) pause(max(0,s));
    T.until = @(t) pause(max(0, t - T.now()));
    T.backend = 'MATLAB';
end
fprintf('[Timing] Backend: %s\n', T.backend);

%% Command log
[cmdPath, cmdBase] = fileparts(cfg.EVENT_FILENAME);
cmdBase = strrep(cmdBase,'_events','_commands');
cmdFile = fullfile(cmdPath,[cmdBase '.tsv']);
cmdFH = fopen(cmdFile,'w');
fprintf(cmdFH, 't_send_getsecs\tcommand\targ_ms\tack\tretries\tmessage\n');

%% Trials
addpath(cfg.PATH_TASK);
if ~(exist('create_trials_table','file')==2)
    error('create_trials_table.m not found on path %s', cfg.PATH_TASK);
end
[cfg, trials, text_wrapped_all] = create_trials_table(cfg);
ntrials = height(trials);

%% Event log
eventFH = fopen(cfg.EVENT_FILENAME,'w');
fprintf(eventFH,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n');

%% GUI
screenSize = get(0,'ScreenSize');
hfig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', ...
    'Position',[0 0 screenSize(3) screenSize(4)], 'NumberTitle','off');
ax = axes('Parent',hfig,'Position',[0 0 1 1],'Visible','off');
hText = text(0.5,0.5,'','Parent',ax,'FontSize',cfg.stim_font_size,'FontWeight','bold',...
    'HorizontalAlignment','center','VerticalAlignment','middle','Units','normalized');
pdiode_square_length = 0.05;
hSquare = annotation('rectangle','FaceColor',[1 1 1],'EdgeColor','none', ...
    'Position',[0, 1-pdiode_square_length, pdiode_square_length, pdiode_square_length]);

setappdata(hfig,'SPACE_FLAG',[]);
setappdata(hfig,'ESC_FLAG',[]);
set(hfig,'WindowKeyPressFcn', @(~,e) ...
    ( strcmpi(e.Key,'space')  && setappdata(hfig,'SPACE_FLAG',true) ) | ...
    ( strcmpi(e.Key,'escape') && setappdata(hfig,'ESC_FLAG',true)  ) );

TRIG_ITI = 1; TRIG_VIS = 2; TRIG_DAF = 4; TRIG_KEY = 8; TRIG_ESC = 16;

%% TCP client handle
c = []; haveDAF = false;
if isfield(cfg,'DAF_TCP') && ~isempty(cfg.DAF_TCP)
    c = cfg.DAF_TCP;
    haveDAF = true;
    fprintf('DAF TCP ready to %s:%d\n', cfg.ENGINE_HOST, cfg.ENGINE_PORT);
else
    warning('DAF_TCP is empty. Running task without sending DAF commands.');
end

% RX buffer for line parsing
if ~isfield(cfg,'NET_RXBUF'), cfg.NET_RXBUF = uint8([]); end
rxbuf = cfg.NET_RXBUF;

% Inline helpers (TCP)
sendStart    = @(ms) netSend(c, sprintf('START %d', round(ms)), ms, cmdFH, cfg, false);
sendStop     = @()  netSend(c, 'STOP', [], cmdFH, cfg, false);
sendPing     = @()  netSend(c, 'PING', [], cmdFH, cfg, true);
sendSyncBeep = @()  netSend(c, 'SYNCBEEP', [], cmdFH, cfg, true);

doDigOut = isfield(cfg,'DIGOUT') && logical(cfg.DIGOUT);

%% Instructions screen
instructions = "INSTRUCTIONS\n\nWhen text appears, read it out loud as accurately as possible.\n\nPress SPACE to begin.";
set(hText,'String',instructions,'FontSize',45,'Color','black'); drawnow;
flipState = 0;
while true
    [space, esc] = KeyPoll(hfig);
    if esc
        flipState = ~flipState;
        log_event(eventFH, doDigOut, T.now(), [], [], 'control', [], TRIG_ESC, 'Key_Esc_At_Instructions', flipState);
        safeQuit(); fclose(eventFH); fclose(cmdFH); close(hfig); return;
    end
    if space
        flipState = ~flipState;
        log_event(eventFH, doDigOut, T.now(), [], [], 'control', [], TRIG_KEY, 'Key_Space', flipState);
        break;
    end
    T.wait(0.01);
end
set(hText,'String',''); drawnow;
t0 = T.now();

% Sync beep (ACK expected)
if haveDAF, sendSyncBeep(); end
flipState = ~flipState;
log_event(eventFH, 0, t0, [], [], [], [], 0, 'Instructions_End', flipState);

%% TSYNC
cfg.ENGINE_OFFSET_S = NaN; cfg.ENGINE_RTT_S = NaN;
if haveDAF
    try
        [offEst, rtt] = do_tsync_tcp(c, @Tnow, @netDrainLines);
        cfg.ENGINE_OFFSET_S = offEst; cfg.ENGINE_RTT_S = rtt;
        fprintf('TSYNC: offset(engine-master)=%.3f ms, RTT=%.3f ms\n', 1000*offEst, 1000*rtt);
    catch ME
        warning('TSYNC failed: %s', message);
    end
end
    function t=Tnow, t=T.now(); end

%% Main trial loop
ITI_S = [1.75, 2.25];
for itrial = 1:ntrials
    isCatch = trials.catch_trial(itrial);
    delay_ms_planned = trials.delay(itrial);

    % ITI
    set(hText,'String','*','Color', tern(~isCatch,[0.7 0.7 0.7],'red'));
    set(hSquare,'FaceColor',[0.3 0.3 0.3]); drawnow;
    tFixOn = T.now();
    flipState = ~flipState;
    log_event(eventFH, 0, tFixOn, [], [], tern(isCatch,'catch','speech'), [], TRIG_ITI, 'Fixation_Cross_Onset', flipState);

    % DAF ON before visual if speech trial
    if haveDAF && ~isCatch
        if cfg.DAF_START_OFFSET_S ~= 0, T.until(tFixOn + cfg.DAF_START_OFFSET_S); end
        sendStart(delay_ms_planned);
        flipState = ~flipState;
        log_event(eventFH, doDigOut, T.now(), [], [], 'speech', [], TRIG_DAF, sprintf('DAF_On_cmd(ms=%d)', delay_ms_planned), flipState);
        drainAppliedAndLog();  % non-blocking
    end

    % Wait ITI
    T.wait(ITI_S(1) + rand*(ITI_S(2)-ITI_S(1)));

    % Visual ON
    set(hSquare,'FaceColor',[0 0 0]);
    set(hText,'String', text_wrapped_all{trials.stim_idx(itrial)}, 'Color','black'); drawnow;
    tVisOn = T.now();
    flipState = ~flipState;
    log_event(eventFH, doDigOut, tVisOn, [], [], tern(isCatch,'catch','speech'), trials.stim{itrial}, TRIG_VIS, 'Visual Onset', flipState);

    % Speaking window
    tSpeakStart = T.now();
    while T.now() - tSpeakStart < cfg.text_stim_dur
        [~, esc] = KeyPoll(hfig);
        if esc
            if haveDAF, sendStop(); drainAppliedAndLog(); end
            flipState = ~flipState;
            log_event(eventFH, doDigOut, T.now(), [], [], tern(isCatch,'catch','speech'), [], TRIG_ESC, 'Key_Esc', flipState);
            safeQuit(); fclose(eventFH); fclose(cmdFH); close(hfig); return
        end
        if haveDAF, drainAppliedAndLog(); end
        T.wait(0.005);
    end

    % DAF OFF
    if haveDAF && ~isCatch
        sendStop();
        flipState = ~flipState;
        log_event(eventFH, doDigOut, T.now(), [], [], 'speech', [], TRIG_DAF, 'DAF_Off_cmd', flipState);
        drainAppliedAndLog();
    end

    % Visual OFF
    set(hText,'String','');
    set(hSquare,'FaceColor',[1 1 1]); drawnow;
    tVisOff = T.now();
    flipState = ~flipState;
    log_event(eventFH, doDigOut, tVisOff, [], [], tern(isCatch,'catch','speech'), [], TRIG_VIS, 'Visual Off', flipState);

    % Append trial row
    if itrial == 1
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter','\t','FileType','text','WriteVariableNames', true);
    else
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter','\t','FileType','text','WriteMode','append','WriteVariableNames', false);
    end

    % Block break UI (unchanged)
    if cfg.n_blocks > 1
        currentBlock = trials.block(itrial);
        blockTrials = find(trials.block == currentBlock);
        if itrial == blockTrials(end) && itrial < ntrials
            flipState = ~flipState;
            log_event(eventFH, doDigOut, T.now(), [], [], 'control', [], 0, sprintf('Block_%d_Break_Start', currentBlock), flipState);
            set(hText,'String',sprintf('Block %d/%d finished.\nPress spacebar to continue.', currentBlock, cfg.n_blocks),'FontSize',28,'Color','blue'); drawnow;
            fprintf('Block %d/%d finished; press spacebar to continue...\n', currentBlock, cfg.n_blocks);
            set(hfig,'WindowKeyPressFcn', @(src,evt) strcmp(evt.Key,'space') && uiresume(hfig));
            uiwait(hfig);
            flipState = ~flipState;
            log_event(eventFH, doDigOut, T.now(), [], [], 'control', [], 0, sprintf('Block_%d_Break_End', currentBlock), flipState);
            set(hfig, 'WindowKeyPressFcn', @(~,e) ...
                ( strcmpi(e.Key,'space') && setappdata(hfig,'SPACE_FLAG',true) ) | ...
                ( strcmpi(e.Key,'escape') && setappdata(hfig,'ESC_FLAG',true) ));
            set(hText,'String',''); drawnow;
        end
    end
end

%% Cleanup
if haveDAF, sendStop(); drainAppliedAndLog(); end
fclose(eventFH); fclose(cmdFH); close(hfig);
fprintf('Task complete.\n');

%% ===== helpers =====
function out = tern(cond,a,b), if cond, out=a; else, out=b; end, end
function safeQuit(), fprintf('ESC pressed → quitting task\n'); end

% NET SEND: write a line; optionally wait for ACK
function netSend(c, line, arg_ms, fh, cfg, expectsAck)
    if nargin<6, expectsAck=false; end
    tSend = T.now(); cmdTxt = string(line); retries=0; ack="NA"; msg="";
    if isempty(c)
        fprintf('[DAF-OFFLINE] %s\n', cmdTxt);
        fprintf(fh, '%.6f\t%s\t%s\t%s\t%d\t%s\n', tSend, cmdTxt, num2strOrEmpty(arg_ms), ack, retries, "no_tcp");
        return
    end
    try
        write(c, uint8([char(cmdTxt) 10])); % '\n'
        if expectsAck
            [ackOK, why] = waitForAck(cfg.NET_ACK_TIMEOUT_S, cfg.NET_MAX_RETRIES);
            if ackOK, ack="ACK"; else, msg=why; end
        end
    catch ME
        msg = "send_error:" + string(ME.message);
    end
    fprintf(fh, '%.6f\t%s\t%s\t%s\t%d\t%s\n', tSend, cmdTxt, num2strOrEmpty(arg_ms), ack, retries, msg);

    function [ok, why] = waitForAck(timeout, maxRetries)
        ok=false; why="timeout_no_ack";
        t0 = T.now(); data = uint8([]);
        while T.now()-t0 < timeout
            data = [data read(c, c.NumBytesAvailable, 'uint8')]; %#ok<AGROW>
            [lines, data] = splitLines(data);
            for k=1:numel(lines)
                if strcmpi(strtrim(char(lines{k})), 'ACK'), ok=true; cfg.NET_RXBUF = data; return; end
            end
            T.wait(0.002);
        end
        % One retry loop if wanted (keep simple: caller sets maxRetries>0 to resend)
        for r=1:maxRetries
            write(c, uint8([char(cmdTxt) 10]));
            t0 = T.now(); 
            while T.now()-t0 < timeout
                data = [data read(c, c.NumBytesAvailable, 'uint8')]; %#ok<AGROW>
                [lines, data] = splitLines(data);
                for k=1:numel(lines)
                    if strcmpi(strtrim(char(lines{k})), 'ACK'), ok=true; cfg.NET_RXBUF = data; return; end
                end
                T.wait(0.002);
            end
        end
        cfg.NET_RXBUF = data;
    end
end

function s = num2strOrEmpty(x), if isempty(x), s=''; else, s=num2str(x); end, end

% TSYNC over TCP (line protocol)
function [offset_EminusM, rtt] = do_tsync_tcp(c, nowFcn, drainFcn)
    tM1 = nowFcn();
    write(c, uint8("TSYNC\n"));
    % wait up to 250 ms for ENGINE_T
    t0 = nowFcn(); tE = NaN;
    while nowFcn()-t0 < 0.25
        lines = drainFcn(true); % non-blocking drain
        for i=1:numel(lines)
            L = strtrim(lines{i});
            if startsWith(L, 'ENGINE_T')
                parts = split(L);
                tE = str2double(parts{2});
                tM2 = nowFcn();
                rtt = tM2 - tM1;
                offset_EminusM = ((tE - tM1) - (tM2 - tE)) / 2;
                return
            end
        end
        T.wait(0.001);
    end
    error('TSYNC: no ENGINE_T response');
end

% Drain any APPLIED lines and log them (non-blocking)
function drainAppliedAndLog()
    if isempty(c) || isnan(cfg.ENGINE_OFFSET_S), return; end
    lines = netDrainLines(false);
    for i=1:numel(lines)
        L = strtrim(lines{i});
        if startsWith(L,'APPLIED ')
            toks = split(L);
            cmd = string(toks{2});
            if cmd=="STOP"
                tE = str2double(toks{3}); arg_ms = [];
            else
                arg_ms = str2double(toks{3});
                tE     = str2double(toks{4});
            end
            tMaster_est = tE - cfg.ENGINE_OFFSET_S;
            flipState = ~flipState;
            log_event(eventFH, doDigOut, tMaster_est, [], [], 'engine', char(cmd), TRIG_DAF, 'DAF_Engine_Applied', flipState);
            fprintf(cmdFH, '%.6f\t%s\t%s\t%s\t%d\t%s\n', ...
                T.now(), ['APPLIED_' char(cmd)], num2strOrEmpty(arg_ms), 'ACK', 0, sprintf('ENGINE_APPLIED_%.6f', tMaster_est));
        end
    end
end

% Read all available bytes, split into lines, optionally include partial
function lines = netDrainLines(includeKeep)
    data = [rxbuf read(c, c.NumBytesAvailable, 'uint8')];
    [lines, leftover] = splitLines(data);
    rxbuf = leftover; %#ok<NASGU>
    cfg.NET_RXBUF = rxbuf; % persist
    if includeKeep && ~isempty(leftover)
        % no-op; we keep partial in buffer
    end
end

% Split by '\n' into cellstr{uint8}, return leftover as uint8
function [lines, leftover] = splitLines(data)
    if isempty(data), lines = {}; leftover = data; return; end
    nl = find(data==10); % '\n'
    if isempty(nl)
        lines = {}; leftover = data; return;
    end
    cut = nl(end);
    chunks = mat2cell(data(1:cut-1), 1, diff([0 nl(:)'-1])); % include anything before each NL
    % Remove any empty chunks caused by adjacent NL
    keep = ~cellfun(@isempty, chunks);
    chunks = chunks(keep);
    lines = cellfun(@(u) {u}, chunks);
    lines = cellfun(@(u) {char(u)}, chunks); % convert to char lines (no NL)
    leftover = data(cut+1:end);
end
end

function [space, esc] = KeyPoll(h)
space = ~isempty(getappdata(h,'SPACE_FLAG'));
esc   = ~isempty(getappdata(h,'ESC_FLAG'));
if space, setappdata(h,'SPACE_FLAG',[]); end
if esc,   setappdata(h,'ESC_FLAG',[]);   end
end
