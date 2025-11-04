function task_daf_master(cfg)
% TASK_DAF_MASTER  (MASTER TASK COMPUTER)
% Runs the Delayed Auditory Feedback (DAF) task, controlling visuals, timing, logging,
% and command communication with a separate DAF engine via USB serial.
%
% Sends ASCII commands over serial to the engine to start/stop delays and synchronize clocks.
% Supports optional Psychtoolbox timing backend for high precision.
%
% Input:
%   cfg - Configuration structure containing parameters, file paths, device handles,
%         and task metadata (set by start_daf_intraop_master and related scripts).
%
% Output:
%   This function handles all live task control; outputs logged data and recorded events to files.
%
% Logs three TSV files:
%  - Events (cfg.EVENT_FILENAME): time-stamped experiment events
%  - Trials (cfg.TRIAL_FILENAME): trial metadata
%  - Commands (derived from cfg.EVENT_FILENAME): command send/ack tracking

%% Validate configuration and set defaults
% Check required folder presence
if ~isfield(cfg,'PATH_TASK') || ~isfolder(cfg.PATH_TASK)
    error('cfg.PATH_TASK missing or invalid.');
end

% Check that essential output file names are provided
if ~isfield(cfg,'EVENT_FILENAME') || ~isfield(cfg,'TRIAL_FILENAME')
    error('cfg EVENT/TRIAL filenames missing.');
end

% Set default values for optional config parameters
if ~isfield(cfg,'USB_BAUDRATE'),        cfg.USB_BAUDRATE = 115200; end
if ~isfield(cfg,'DAF_ACK_TIMEOUT_S'),   cfg.DAF_ACK_TIMEOUT_S = 0.10; end
if ~isfield(cfg,'DAF_MAX_RETRIES'),     cfg.DAF_MAX_RETRIES = 0; end
if ~isfield(cfg,'DAF_START_OFFSET_S'),  cfg.DAF_START_OFFSET_S = 0; end
if ~isfield(cfg,'text_stim_dur'),       cfg.text_stim_dur = 10; end
if ~isfield(cfg,'n_blocks'),            cfg.n_blocks = 1; end

%% Setup timing function backend: Psychtoolbox (PTB) or MATLAB native timer
usePTB = false;
if isfield(cfg,'PTB')  % Interpret PTB field as boolean or string true
    if islogical(cfg.PTB), usePTB = cfg.PTB;
    elseif ischar(cfg.PTB) || isstring(cfg.PTB)
        usePTB = any(strcmpi(string(cfg.PTB), ["true","on","ptb","1"]));
    end
end

% Configure timing functions for experiment
if usePTB && exist('GetSecs','file')>0 && exist('WaitSecs','file')>0
    T.now   = @GetSecs;                        % High precision current time
    T.wait  = @(s) WaitSecs(max(0,s));         % Wait for seconds s
    T.until = @(t) WaitSecs('UntilTime', t);   % Wait until absolute time t
    T.backend = 'PTB';
else
    t0 = tic;                                  % Start baseline time
    T.now   = @() toc(t0);                     % Relative current time in sec
    T.wait  = @(s) pause(max(0,s));            % Wait via pause
    T.until = @(t) pause(max(0, t - T.now())); % Wait until absolute time
    T.backend = 'MATLAB';
end
fprintf('[Timing] Backend: %s\n', T.backend);

%% Open command log file to record serial command sends/ack
[cmdPath, cmdBase] = fileparts(cfg.EVENT_FILENAME);
cmdBase = strrep(cmdBase,'_events','_commands');
cmdFile = fullfile(cmdPath,[cmdBase '.tsv']);
cmdFH = fopen(cmdFile,'w');
fprintf(cmdFH, 't_send_getsecs\tcommand\targ_ms\tack\tretries\tmessage\n'); % Write tab-separated header line to the commands log

%% Load and prepare trial table
addpath(cfg.PATH_TASK);
if ~(exist('create_trials_table','file')==2)
    error('create_trials_table.m not found on path %s', cfg.PATH_TASK);
end
[cfg, trials, text_wrapped_all] = create_trials_table(cfg); % Create and load trial parameters table and wrapped text for display
ntrials = height(trials);

%% Open event log file and write header line
eventFH = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFH,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n');

%% Setup graphics (visuals, stimulus text, photodiode square, keyboard callbacks)
screenSize = get(0,'ScreenSize');
hfig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', 'Position',[0 0 screenSize(3) screenSize(4)], 'NumberTitle','off');

% Create full-figure invisible axes for holding text
ax = axes('Parent',hfig,'Position',[0 0 1 1],'Visible','off');

% Create text object centered on figure for stimuli
hText = text(0.5,0.5,'','Parent',ax,'FontSize',cfg.stim_font_size,'FontWeight','bold', 'HorizontalAlignment','center','VerticalAlignment','middle','Units','normalized');

% Small white square for photodiode timing marker (upper-left corner)
pdiode_square_length = 0.05;
hSquare = annotation('rectangle','FaceColor',[1 1 1],'EdgeColor','none', 'Position',[0, 1-pdiode_square_length, pdiode_square_length, pdiode_square_length]);

% Configure keypress event handling for space and escape keys
setappdata(hfig,'__SPACE__',[]);
setappdata(hfig,'__ESC__',[]);
set(hfig,'WindowKeyPressFcn', @(~,e) ...
    ( strcmpi(e.Key,'space')  && setappdata(hfig,'__SPACE__',true) ) | ...
    ( strcmpi(e.Key,'escape') && setappdata(hfig,'__ESC__',true)  ) );

%% Define trigger code constants for event types
TRIG_ITI = 1; % Fixation cross display
TRIG_VIS = 2; % Visual stimulus onset
TRIG_DAF = 4; % DAF audio playback event
TRIG_KEY = 8; % Key press event (space)
TRIG_ESC = 16; % Escape pressed

%% Setup USB serial for communication with DAF engine (empty if unavailable)
% cfg.DAF_SERIAL is expected to be a serialport object connected to the DAF engine's USB serial interface
% This serial port enables command/control communication between the master task computer and the DAF engine
s = [];
if isfield(cfg,'DAF_SERIAL')
    s = cfg.DAF_SERIAL;
end

haveDAF = ~isempty(s);
if haveDAF
    try
        configureTerminator(s,"LF"); % Ensure proper newline framing for serial lines
    catch
        % ignore errors here
    end
    fprintf('DAF USB ready on %s @ %d\n', s.Port, cfg.USB_BAUDRATE);
else
    warning('DAF_SERIAL is empty. Running task without sending DAF commands.');
end

% Define simple inline helper functions to send ASCII commands to the DAF engine:
% sendStart(ms): send "START <ms>" to begin delayed playback at <ms> delay
% sendStop(): send "STOP" command to halt delayed playback immediately
% sendPing(): send "PING" command, expecting an "ACK" reply (used for liveness checking)
% sendSyncBeep(): sends sync beeps to daf engine for external mic syncing
sendStart = @(ms) usbSend(s, sprintf('START %d', round(ms)), ms, cmdFH, cfg);
sendStop  = @()  usbSend(s, 'STOP', [], cmdFH, cfg);
sendPing  = @()  usbSend(s, 'PING', [], cmdFH, cfg, true);
sendSyncBeep = @() usbSend(s, 'SYNCBEEP', [], cmdFH, cfg);

% Check if digital output exists (e.g., Ripple system)
doDigOut = isfield(cfg,'DIGOUT') && logical(cfg.DIGOUT);

%% Show instructions screen and wait for space keypress or escape abort
instructions = "INSTRUCTIONS\n\nWhen text appears, read it out loud as accurately as possible.\n\nPress SPACE to begin.";
set(hText,'String',instructions,'FontSize',45,'Color','black'); drawnow;
flipState = 0;

% Wait for SPACE (ESC abort)
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

set(hText,'String','');
drawnow;
t0 = T.now(); % Task start time anchor

% Send sync beep command to DAF engine to play sync tone on audio output
sendSyncBeep();

flipState = ~flipState;
log_event(eventFH, 0, t0, [], [], [], [], 0, 'Instructions_End', flipState);

%% Synchronize clocks with DAF engine (TSYNC)
cfg.ENGINE_OFFSET_S = NaN; cfg.ENGINE_RTT_S = NaN;
if haveDAF
    try
        [offEst, rtt] = do_tsync(s);
        cfg.ENGINE_OFFSET_S = offEst; % engine_time ≈ master_time + offset
        cfg.ENGINE_RTT_S    = rtt;
        fprintf('TSYNC: offset(engine-master)=%.3f ms, RTT=%.3f ms\n', 1000*offEst, 1000*rtt);
    catch ME
        warning('TSYNC failed: %s', ME);
    end
end

%% Main trial loop
ITI_S = [1.75, 2.25]; % Inter-trial interval range in seconds

for itrial = 1:ntrials
    isCatch = trials.catch_trial(itrial);
    delay_ms_planned = trials.delay(itrial);
    
    % ITI + fixation
    set(hText,'String','*','Color', tern(~isCatch,[0.7 0.7 0.7],'red'));
    set(hSquare,'FaceColor',[0.3 0.3 0.3]);
    drawnow;
    tFixOn = T.now();
    flipState = ~flipState;
    log_event(eventFH, 0, tFixOn, [], [], tern(isCatch,'catch','speech'), [], TRIG_ITI, 'Fixation_Cross_Onset', flipState);

    % Send DAF ON command relative to fixation onset (if not catch trial)
    if haveDAF && ~isCatch
        if cfg.DAF_START_OFFSET_S ~= 0
            T.until(tFixOn + cfg.DAF_START_OFFSET_S);
        end
        sendStart(delay_ms_planned);
        flipState = ~flipState;
        log_event(eventFH, doDigOut, T.now(), [], [], 'speech', [], TRIG_DAF, sprintf('DAF_On_cmd(ms=%d)', delay_ms_planned), flipState);
        drainAppliedAndLog();
    end

    % Keep fixation cross on for the randomly sampled ITI duration
    itiDur = ITI_S(1) + rand*(ITI_S(2)-ITI_S(1));
    T.wait(itiDur);

    % Visual on, fixation cross off
    set(hSquare,'FaceColor',[0 0 0]);
    set(hText,'String', text_wrapped_all{trials.stim_idx(itrial)}, 'Color','black');
    drawnow;
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

    % Visual OFF, reset photodiode square
    set(hText,'String','');
    set(hSquare,'FaceColor',[1 1 1]);
    drawnow;
    tVisOff = T.now();
    flipState = ~flipState;
    log_event(eventFH, doDigOut, tVisOff, [], [], tern(isCatch,'catch','speech'), [], TRIG_VIS, 'Visual Off', flipState);

    % Append current trial row to trial results file
    if itrial == 1
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter','\t','FileType','text', 'WriteVariableNames', true);
    else
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter','\t','FileType','text', 'WriteMode','append', 'WriteVariableNames', false);
    end

    if cfg.n_blocks > 1
        currentBlock = trials.block(itrial);  % Current trial's block number
        blockTrials = find(trials.block == currentBlock);  % Trial indices in this block
        
        % If this is the last trial in the block and not the last overall trial
        if itrial == blockTrials(end) && itrial < ntrials
            flipState = ~flipState;
            log_event(eventFH, doDigOut, T.now(), [], [], 'control', [], 0, sprintf('Block_%d_Break_Start', currentBlock), flipState);

            % Display break message on screen and console
            set(hText, 'String', sprintf('Block %d/%d finished.\nPress spacebar to continue.', ...
                currentBlock, cfg.n_blocks), 'FontSize', 28, 'Color', 'blue');
            drawnow;
            fprintf('Block %d/%d finished; press spacebar to continue...\n', currentBlock, cfg.n_blocks);
            
            % Change keypress callback to catch space and release uiwait
            set(hfig, 'WindowKeyPressFcn', @(src,evt) ...
                strcmp(evt.Key, 'space') && uiresume(hfig));
            uiwait(hfig);  % Wait for spacebar press
            
            flipState = ~flipState;
            log_event(eventFH, doDigOut, T.now(), [], [], 'control', [], 0, sprintf('Block_%d_Break_End', currentBlock), flipState);
            % Restore original callbacks
            set(hfig, 'WindowKeyPressFcn', @(~,e) ...
                ( strcmpi(e.Key,'space') && setappdata(hfig,'__SPACE__',true) ) | ...
                ( strcmpi(e.Key,'escape') && setappdata(hfig,'__ESC__',true) ));
            set(hText,'String',''); drawnow;
        end
    end
end

%% Cleanup
if haveDAF
    sendStop();
    drainAppliedAndLog();
end
fclose(eventFH);
fclose(cmdFH);
close(hfig);
fprintf('Task complete.\n');

%% ====== nested helpers ======

% Simple ternary operator
function out = tern(cond, a, b)
    if cond, out=a; else, out=b; end
end

% Send ASCII command string via USB serial to DAF engine; optionally wait for ACK
% This function sends an arbitrary ASCII command line over the serialport object
% If expectsAck is true (default false), it waits for acknowledgment "ACK" from the engine, retrying up to cfg.DAF_MAX_RETRIES
% The function logs the command send time, retries, ACK status, and any error messages to cmdFH (commands log file)
% It flushes the serial port before writing to clear any stale buffered data, ensuring commands are processed cleanly
function usbSend(sp, line, arg_ms, fh, cfg, expectsAck)
    if nargin < 6, expectsAck = false; end
    tSend = T.now();
    cmdTxt = string(line);
    retries = 0; ack = "NA"; msg = "";

    % If serial port not connected, log no_serial and skip sending
    if isempty(sp)
        fprintf('[DAF-OFFLINE] %s\n', cmdTxt);
        fprintf(fh, '%.6f\t%s\t%s\t%s\t%d\t%s\n', tSend, cmdTxt, num2strOrEmpty(arg_ms), ack, retries, "no_serial");
        return
    end
    try
        flush(sp); % Clear input/output buffers for clean start
        writeline(sp, cmdTxt); % Send ASCII command line
        if expectsAck
            got = tryReadline(sp, cfg.DAF_ACK_TIMEOUT_S); % Read line response with timeout (cfg.DAF_ACK_TIMEOUT_S)
            if ~isempty(got) && strcmpi(strtrim(got),'ACK')
                ack = "ACK";
            else
                while retries < cfg.DAF_MAX_RETRIES && ~strcmp(ack,"ACK") % Retry sending while no ACK received up to max retries
                    retries = retries + 1;
                    flush(sp);
                    writeline(sp, cmdTxt);
                    got = tryReadline(sp, cfg.DAF_ACK_TIMEOUT_S);
                    if ~isempty(got) && strcmpi(strtrim(got),'ACK'), ack = "ACK"; end
                end
                if ~strcmp(ack,"ACK")
                    msg = "timeout_no_ack"; % Log failure reason
                end
            end
        end
    catch ME
        msg = "send_error:" + string(ME.message); % Catch and log any exceptions during send attempt
    end
    fprintf(fh, '%.6f\t%s\t%s\t%s\t%d\t%s\n', tSend, cmdTxt, num2strOrEmpty(arg_ms), ack, retries, msg);
end

% Convert number to string or empty string for logging
function s = num2strOrEmpty(x)
    if isempty(x), s = ''; else, s = num2str(x); end
end

% Try reading one line from serial port with timeout
function got = tryReadline(sp, timeout_s)
    got = "";
    if isempty(sp), return; end
    t0 = T.now();
    while T.now()-t0 < timeout_s
        try
            if sp.NumBytesAvailable > 0
                got = readline(sp); return
            end
        catch
            got = ""; return
        end
        T.wait(0.002);
    end
end

% Print message and quit task when ESC pressed
function safeQuit()
    fprintf('ESC pressed → quitting task\n');
end

% TSYNC command implementation:
% Send "TSYNC" to engine, read "ENGINE_T <time>" reply, compute clock offset
function [offset_EminusM, rtt, tM1, tE, tM2] = do_tsync(sp)
    % Send TSYNC and compute offset using: offset = ((tE - tM1) - (tM2 - tE)) / 2
    % where tM1/tM2 are master GetSecs() before/after read, and tE is engine time in seconds
    if isempty(sp), error('No serial handle for TSYNC'); end
    tM1 = T.now();
    flush(sp);
    writeline(sp, "TSYNC");
    % wait for "ENGINE_T <tE>"
    got = "";
    t0 = T.now();
    while T.now()-t0 < 0.25
        if sp.NumBytesAvailable > 0
            got = readline(sp); break
        end
        T.wait(0.001);
    end
    tM2 = T.now();
    if isempty(got) || ~startsWith(strtrim(got),"ENGINE_T")
        error('TSYNC: no ENGINE_T response');
    end
    parts = split(strtrim(got));
    tE = str2double(parts{2}); % engine seconds since its start
    rtt = tM2 - tM1;
    % NTP-style offset (engine minus master, in seconds):
    offset_EminusM = ((tE - tM1) - (tM2 - tE)) / 2;
end

% Drain any "APPLIED" messages from engine serial buffer and log them
function drainAppliedAndLog()
    if isempty(s) || isnan(cfg.ENGINE_OFFSET_S), return; end
    recs = {};
    % Non blocking drain
    while s.NumBytesAvailable > 0
        line = strtrim(readline(s));
        if startsWith(line,'APPLIED ')
            toks = split(line);
            cmd = string(toks{2});
            if cmd=="STOP"
                tE = str2double(toks{3}); arg_ms = [];
            else
                arg_ms = str2double(toks{3});
                tE     = str2double(toks{4});
            end
            tMaster_est = tE - cfg.ENGINE_OFFSET_S;
            flipState = ~flipState;  % uses outer var
            log_event(eventFH, doDigOut, tMaster_est, [], [], 'engine', char(cmd), TRIG_DAF, 'DAF_Engine_Applied', flipState);
            fprintf(cmdFH, '%.6f\t%s\t%s\t%s\t%d\t%s\n', ...
                T.now(), ['APPLIED_' char(cmd)], num2strOrEmpty(arg_ms), 'ACK', 0, sprintf('ENGINE_APPLIED_%.6f', tMaster_est));
        end
    end

    % Log any records
    for i = 1:numel(recs)
        tMaster_est = recs{i}.tE - cfg.ENGINE_OFFSET_S; % convert engine seconds to master GetSecs seconds
        % Events log: encode as engine-applied event
        if isempty(recs{i}.arg_ms)
            valStr = [];
        else
            valStr = recs{i}.arg_ms;
        end
        % inside drainAppliedAndLog()
        flipState = ~flipState;
        log_event(eventFH, doDigOut, tMaster_est, [], [], 'engine', char(recs{i}.cmd), TRIG_DAF, 'DAF_Engine_Applied', flipState);
        % Commands log: mirror as an ACK-like row
        fprintf(cmdFH, '%.6f\t%s\t%s\t%s\t%d\t%s\n', ...
            T.now(), ['APPLIED_' char(recs{i}.cmd)], num2strOrEmpty(valStr), 'ACK', 0, sprintf('ENGINE_APPLIED_%.6f', tMaster_est));
    end
end
end

% Poll keyboard appdata to detect edge-triggered space and escape key events
function [space, esc] = KeyPoll(h)
    space = ~isempty(getappdata(h,'__SPACE__'));
    esc   = ~isempty(getappdata(h,'__ESC__'));
    if space, setappdata(h,'__SPACE__',[]); end
    if esc,   setappdata(h,'__ESC__',[]); end
end