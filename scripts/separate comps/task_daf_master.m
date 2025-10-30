function task_daf_master(cfg)
% TASK_DAF_MASTER  (MASTER TASK COMPUTER)
% Runs the DAF task (visuals, timing, logging) and controls a remote DAF engine via USB.
% - Sends:  START <ms>   (begin DAF at delay)
%           SET <ms>     (change delay live / pre-arm)
%           STOP         (stop DAF)
%           PING         (optional liveness check → expects ACK)
%           TSYNC        (engine replies ENGINE_T <sec>; used to align clocks)
%
% Expects:
%   cfg.DAF_SERIAL  = serialport handle opened by start_daf_intraop_master (or [])
%   cfg.EVENT_FILENAME, cfg.TRIAL_FILENAME, cfg.PATH_TASK, cfg.daf_stim_file, etc.
%
% Logging:
%   Events   → cfg.EVENT_FILENAME (BIDS-like .tsv)
%   Trials   → cfg.TRIAL_FILENAME
%   Commands → <BASE_NAME>commands.tsv in cfg.PATH_LOG
%
% New in this version:
%   - Clock sync with engine (TSYNC) to estimate engine-master offset/RTT.
%   - Engine sends "APPLIED ..." lines with engine timestamps when it applies START/SET/STOP.
%   - Master drains and logs APPLIED, converting to master time using the offset.

%% ----- Setup & files -----
if ~isfield(cfg,'PATH_TASK') || ~isfolder(cfg.PATH_TASK)
    error('cfg.PATH_TASK missing or invalid.');
end
if ~isfield(cfg,'EVENT_FILENAME') || ~isfield(cfg,'TRIAL_FILENAME')
    error('cfg EVENT/TRIAL filenames missing.');
end
if ~isfield(cfg,'USB_BAUDRATE'),        cfg.USB_BAUDRATE = 115200; end
if ~isfield(cfg,'DAF_ACK_TIMEOUT_S'),   cfg.DAF_ACK_TIMEOUT_S = 0.10; end
if ~isfield(cfg,'DAF_MAX_RETRIES'),     cfg.DAF_MAX_RETRIES = 0; end
if ~isfield(cfg,'DAF_START_OFFSET_S'),  cfg.DAF_START_OFFSET_S = 0; end
if ~isfield(cfg,'text_stim_dur'),       cfg.text_stim_dur = 10; end
if ~isfield(cfg,'n_blocks'),            cfg.n_blocks = 1; end

% Command log
[cmdPath, cmdBase] = fileparts(cfg.EVENT_FILENAME);
cmdBase = strrep(cmdBase,'_events','_commands');
cmdFile = fullfile(cmdPath,[cmdBase '.tsv']);
cmdFH = fopen(cmdFile,'w');
fprintf(cmdFH, 't_send_getsecs\tcommand\targ_ms\tack\tretries\tmessage\n');

% Trial table
addpath(cfg.PATH_TASK);
if ~(exist('create_trials_table','file')==2)
    error('create_trials_table.m not found on path %s', cfg.PATH_TASK);
end
[cfg, trials, text_wrapped_all] = create_trials_table(cfg);  %#ok<ASGLU>
ntrials = height(trials);

% Event file
eventFH = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFH,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n');

%% ----- Visuals (no audio here) -----
KbName('UnifyKeyNames');
keyEsc   = KbName('ESCAPE');
keySpace = KbName('space');

screenSize = get(0,'ScreenSize');
hfig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', ...
              'Position',[0 0 screenSize(3) screenSize(4)], 'NumberTitle','off');
ax = axes('Parent',hfig,'Position',[0 0 1 1],'Visible','off');
hText = text(0.5,0.5,'','Parent',ax,'FontSize',cfg.stim_font_size,'FontWeight','bold', ...
             'HorizontalAlignment','center','VerticalAlignment','middle','Units','normalized');
pdiode_square_length = 0.05;
hSquare = annotation('rectangle','FaceColor',[1 1 1],'EdgeColor','none', ...
    'Position',[0, 1-pdiode_square_length, pdiode_square_length, pdiode_square_length]);

% Simple event code scheme (parity with prior constants)
TRIG_ITI=1; TRIG_VIS=2; TRIG_DAF=4; TRIG_KEY=8; TRIG_ESC=16;

%% ----- USB to DAF engine -----
s = []; if isfield(cfg,'DAF_SERIAL'), s = cfg.DAF_SERIAL; end
haveDAF = ~isempty(s);
if haveDAF
    try
        configureTerminator(s,"LF"); % ensure newline framing
    catch, end
    fprintf('DAF USB ready on %s @ %d\n', s.Port, cfg.USB_BAUDRATE);
else
    warning('DAF_SERIAL is empty. Running task without sending DAF commands.');
end

sendStart = @(ms)usbSend(s, sprintf('START %d', round(ms)), ms, cmdFH, cfg);
sendSet   = @(ms)usbSend(s, sprintf('SET %d',   round(ms)), ms, cmdFH, cfg);
sendStop  = @()  usbSend(s, 'STOP', [], cmdFH, cfg);
sendPing  = @()  usbSend(s, 'PING', [], cmdFH, cfg, true); % expects ACK

%% ----- Instructions & start -----
instructions = "INSTRUCTIONS\n\nWhen text appears, read it out loud as accurately as possible.\n\nPress SPACE to begin.";
set(hText,'String',instructions,'FontSize',45,'Color','black'); drawnow;
flipState = 0;

% Wait for SPACE (ESC abort)
while true
    KbReleaseWait; [isDown, ~, kc] = KbCheck;
    if isDown && kc(keySpace), break; end
    if isDown && kc(keyEsc), safeQuit(); fclose(eventFH); fclose(cmdFH); close(hfig); return; end
    WaitSecs(0.01);
end
set(hText,'String',''); drawnow;
t0 = GetSecs(); %#ok<NASGU>  % local anchor if you want it; events are logged in absolute GetSecs time

% Log end-of-instructions event
flipState = ~flipState;
log_event(eventFH, 0, t0, [], [], [], [], 0, 'Instructions_End', flipState);

%% ----- One-time TSYNC with engine -----
cfg.ENGINE_OFFSET_S = NaN; cfg.ENGINE_RTT_S = NaN;
if haveDAF
    try
        [offEst, rtt] = do_tsync(s);
        cfg.ENGINE_OFFSET_S = offEst;     % engine_time ≈ master_time + offset
        cfg.ENGINE_RTT_S    = rtt;
        fprintf('TSYNC: offset(engine-master)=%.3f ms, RTT=%.3f ms\n', 1000*offEst, 1000*rtt);
    catch ME
        warning('TSYNC failed: %s', ME);
    end
end

%% ----- Main trial loop -----
ITI_S = [1.75, 2.25];
for itrial = 1:ntrials
    isCatch = trials.catch_trial(itrial);
    delay_ms_planned = trials.delay(itrial);

    % Optional: pre-arm engine with desired delay during ITI
    if haveDAF && ~isCatch
        sendSet(delay_ms_planned);
        drainAppliedAndLog(); % log any APPLIED SET immediately
    end

    % ITI + fixation
    set(hText,'String','*','Color', tern(~isCatch,[0.7 0.7 0.7],'red'));
    set(hSquare,'FaceColor',[0.3 0.3 0.3]); drawnow;
    tFixOn = GetSecs();
    flipState = ~flipState;
    log_event(eventFH, 0, tFixOn, [], [], tern(isCatch,'catch','speech'), [], TRIG_ITI, 'Fixation_Cross_Onset', flipState);

    itiDur = ITI_S(1) + rand*(ITI_S(2)-ITI_S(1));
    WaitSecs(itiDur);

    % Visual ON
    set(hSquare,'FaceColor',[0 0 0]); % black for photodiode
    set(hText,'String', text_wrapped_all{trials.stim_idx(itrial)}, 'Color','black'); drawnow;
    tVisOn = GetSecs();
    flipState = ~flipState;
    log_event(eventFH, 0, tVisOn, [], [], tern(isCatch,'catch','speech'), trials.stim{itrial}, TRIG_VIS, 'Visual Onset', flipState);

    % DAF START at chosen offset relative to visual onset (speech only)
    if haveDAF && ~isCatch
        if cfg.DAF_START_OFFSET_S ~= 0
            WaitSecs('UntilTime', tVisOn + cfg.DAF_START_OFFSET_S);
        end
        sendStart(delay_ms_planned);
        flipState = ~flipState;
        log_event(eventFH, 0, GetSecs(), [], [], 'speech', delay_ms_planned, TRIG_DAF, 'DAF_On (command sent)', flipState);
        drainAppliedAndLog(); % capture APPLIED START promptly
    end

    % Speaking window (visual only)
    tSpeakStart = GetSecs();
    while GetSecs() - tSpeakStart < cfg.text_stim_dur
        [isDown, ~, kc] = KbCheck;
        if isDown && kc(keyEsc)
            if haveDAF, sendStop(); drainAppliedAndLog(); end
            flipState = ~flipState;
            log_event(eventFH, 0, GetSecs(), [], [], tern(isCatch,'catch','speech'), [], TRIG_ESC, 'Escape', flipState);
            safeQuit(); fclose(eventFH); fclose(cmdFH); close(hfig); return
        end
        % opportunistically drain any APPLIED lines during the window
        if haveDAF, drainAppliedAndLog(); end
        WaitSecs(0.005);
    end

    % DAF OFF
    if haveDAF && ~isCatch
        sendStop();
        flipState = ~flipState;
        log_event(eventFH, 0, GetSecs(), [], [], 'speech', [], TRIG_DAF, 'DAF_Off (command sent)', flipState);
        drainAppliedAndLog(); % capture APPLIED STOP
    end

    % Visual OFF
    set(hText,'String',''); set(hSquare,'FaceColor',[1 1 1]); drawnow;
    tVisOff = GetSecs();
    flipState = ~flipState;
    log_event(eventFH, 0, tVisOff, [], [], tern(isCatch,'catch','speech'), [], TRIG_VIS, 'Visual Off', flipState);

    % Append trial row
    if itrial == 1
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter','\t','FileType','text', 'WriteVariableNames', true);
    else
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter','\t','FileType','text', 'WriteMode','append', 'WriteVariableNames', false);
    end

    % (Optional: per-block breaks here based on cfg.n_blocks)
end

%% ----- Cleanup -----
if haveDAF, sendStop(); drainAppliedAndLog(); end
fclose(eventFH); fclose(cmdFH);
close(hfig);
fprintf('Task complete.\n');

%% ====== nested helpers ======
    function out = tern(cond, a, b)
        if cond, out=a; else, out=b; end
    end

    function usbSend(sp, line, arg_ms, fh, cfg, expectsAck)
        % Send a single ASCII line to DAF engine; optionally expect an ACK (for PING).
        if nargin < 6, expectsAck = false; end
        tSend = GetSecs();
        cmdTxt = string(line);
        retries = 0; ack = "NA"; msg = "";
        if isempty(sp)
            fprintf('[DAF-OFFLINE] %s\n', cmdTxt);
            fprintf(fh, '%.6f\t%s\t%s\t%s\t%d\t%s\n', tSend, cmdTxt, num2strOrEmpty(arg_ms), ack, retries, "no_serial");
            return
        end
        try
            writeline(sp, cmdTxt);
            if expectsAck
                got = tryReadline(sp, cfg.DAF_ACK_TIMEOUT_S);
                if ~isempty(got) && strcmpi(strtrim(got),'ACK')
                    ack = "ACK";
                else
                    while retries < cfg.DAF_MAX_RETRIES && ~strcmp(ack,"ACK")
                        retries = retries + 1;
                        writeline(sp, cmdTxt);
                        got = tryReadline(sp, cfg.DAF_ACK_TIMEOUT_S);
                        if ~isempty(got) && strcmpi(strtrim(got),'ACK'), ack = "ACK"; end
                    end
                    if ~strcmp(ack,"ACK")
                        msg = "timeout_no_ack";
                    end
                end
            end
        catch ME
            msg = "send_error:" + string(ME.message);
        end
        fprintf(fh, '%.6f\t%s\t%s\t%s\t%d\t%s\n', tSend, cmdTxt, num2strOrEmpty(arg_ms), ack, retries, msg);
    end

    function s = num2strOrEmpty(x)
        if isempty(x), s = ''; else, s = num2str(x); end
    end

    function got = tryReadline(sp, timeout_s)
        got = "";
        if isempty(sp), return; end
        t0 = GetSecs();
        while GetSecs()-t0 < timeout_s
            try
                if sp.NumBytesAvailable > 0
                    got = readline(sp); return
                end
            catch
                got = ""; return
            end
            WaitSecs(0.002);
        end
    end

    function safeQuit()
        fprintf('ESC pressed → quitting task\n');
    end

    function [offset_EminusM, rtt, tM1, tE, tM2] = do_tsync(sp)
        % Send TSYNC and compute offset using: offset = ((tE - tM1) - (tM2 - tE)) / 2
        % where tM1/tM2 are master GetSecs() before/after read, and tE is engine time in seconds
        if isempty(sp), error('No serial handle for TSYNC'); end
        tM1 = GetSecs();
        writeline(sp, "TSYNC");
        % wait for "ENGINE_T <tE>"
        got = "";
        t0 = GetSecs();
        while GetSecs()-t0 < 0.25
            if sp.NumBytesAvailable > 0
                got = readline(sp); break
            end
            WaitSecs(0.001);
        end
        tM2 = GetSecs();
        if isempty(got) || ~startsWith(strtrim(got),"ENGINE_T")
            error('TSYNC: no ENGINE_T response');
        end
        parts = split(strtrim(got));
        tE = str2double(parts{2}); % engine seconds since its start
        rtt = tM2 - tM1;
        % NTP-style offset (engine minus master, in seconds):
        offset_EminusM = ((tE - tM1) - (tM2 - tE)) / 2;
    end

    function drainAppliedAndLog()
        % Drain any "APPLIED ..." lines from engine, convert to master time, and log.
        if isempty(s) || isnan(cfg.ENGINE_OFFSET_S), return; end
        recs = {};
        % Non-blocking drain
        while s.NumBytesAvailable > 0
            line = strtrim(readline(s));
            if startsWith(line,'APPLIED ')
                toks = split(line);
                % Forms:
                % APPLIED START <ms> <tE>
                % APPLIED SET   <ms> <tE>
                % APPLIED STOP        <tE>
                cmd  = string(toks{2});
                if cmd=="STOP"
                    tE = str2double(toks{3});
                    arg_ms = [];
                else
                    arg_ms = str2double(toks{3});
                    tE     = str2double(toks{4});
                end
                recs{end+1} = struct('cmd',cmd,'arg_ms',arg_ms,'tE',tE); %#ok<AGROW>
            elseif startsWith(line,'ENGINE_T')
                % leftover TSYNC responses — ignore here
            else
                % ignore other async text
            end
        end

        % Log any records
        for i = 1:numel(recs)
            tMaster_est = recs{i}.tE - cfg.ENGINE_OFFSET_S; % convert engine seconds -> master GetSecs seconds
            % Events log: encode as engine-applied event
            flipState = ~flipState; %#ok<NASGU>
            if isempty(recs{i}.arg_ms)
                valStr = [];
            else
                valStr = recs{i}.arg_ms;
            end
            log_event(eventFH, 0, tMaster_est, [], [], 'engine', char(recs{i}.cmd), TRIG_DAF, 'DAF_Engine_Applied', flipState);
            % Commands log: mirror as an ACK-like row
            fprintf(cmdFH, '%.6f\t%s\t%s\t%s\t%d\t%s\n', ...
                GetSecs(), ['APPLIED_' char(recs{i}.cmd)], num2strOrEmpty(valStr), 'ACK', 0, sprintf('ENGINE_APPLIED_%.6f', tMaster_est));
        end
    end
end
