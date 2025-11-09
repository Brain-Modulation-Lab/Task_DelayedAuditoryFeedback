function task_daf_MIDI(cfg)
% Runs the Delayed Auditory Feedback (DAF) task, controlling visuals, timing, logging,
% and MIDI control of Eventide H90
%
% Supports optional Psychtoolbox timing backend for high precision.
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
if ~isfield(cfg,'DAF_START_OFFSET_S'), cfg.DAF_START_OFFSET_S = 0; end
if ~isfield(cfg,'text_stim_dur'),      cfg.text_stim_dur      = 10; end
if ~isfield(cfg,'n_blocks'),           cfg.n_blocks           = 1;  end

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
fprintf(cmdFH, 't_send_getsecs\tcommand\targ1\targ2\tretries\tmessage\n'); % Write tab-separated header line to the commands log

%% Load and prepare trial table
addpath(cfg.PATH_TASK);
if ~(exist('create_trials_table','file')==2)
    error('create_trials_table.m not found on path %s', cfg.PATH_TASK);
end
[cfg, trials, text_wrapped_all] = create_trials_table(cfg); % Create and load trial parameters table and wrapped text for display
ntrials = height(trials);

% Ensure a 'block' column exists for break handling
if cfg.n_blocks < 1, cfg.n_blocks = 1; end
if ~ismember('block', trials.Properties.VariableNames)
    if cfg.n_blocks == 1
        trials.block = ones(ntrials,1,'uint16');
    else
        edges = round(linspace(0, ntrials, cfg.n_blocks+1));
        blockVec = zeros(ntrials,1,'uint16');
        for b = 1:cfg.n_blocks
            if edges(b) < edges(b+1)
                blockVec(edges(b)+1 : edges(b+1)) = b;
            end
        end
        % In rare rounding cases, fill any zeros with last nonzero
        if any(blockVec==0)
            last = 1;
            for j = 1:ntrials
                if blockVec(j)==0, blockVec(j)=last; else, last=blockVec(j); end
            end
        end
        trials.block = blockVec;
    end
end

%% Open event log file and write header line
eventFH = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFH,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n');

%% Setup graphics (visuals, stimulus text, photodiode square, keyboard callbacks)
screenSize = get(0,'ScreenSize');
hfig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', 'Position',[0 0 screenSize(3) screenSize(4)], 'NumberTitle','off');

% Create full-figure invisible axes for holding text
ax = axes('Parent',hfig,'Position',[0 0 1 1],'Visible','off');

% Create text object centered on figure for stimuli
hText = text(0.5,0.5,'','Parent',ax,...
    'FontSize',cfg.stim_font_size,'FontWeight','bold',...
    'HorizontalAlignment','center','VerticalAlignment','middle',...
    'Units','normalized','Interpreter','none');

% Small white square for photodiode timing marker (upper-left corner)
pdiode_square_length = 0.05;
hSquare = annotation('rectangle','FaceColor',[1 1 1],'EdgeColor','none', 'Position',[0, 1-pdiode_square_length, pdiode_square_length, pdiode_square_length]);

% Configure keypress event handling for space and escape keys
setappdata(hfig,'SPACE_FLAG',[]);
setappdata(hfig,'ESC_FLAG',[]);
set(hfig,'WindowKeyPressFcn', @onKey);

function onKey(~, e)
    k = lower(e.Key);
    if strcmp(k,'space')
        setappdata(hfig,'SPACE_FLAG', true);
    elseif strcmp(k,'escape')
        setappdata(hfig,'ESC_FLAG', true);
    end
end

%% Define trigger code constants for event types
TRIG_ITI = 1; % Fixation cross display
TRIG_VIS = 2; % Visual stimulus onset
TRIG_DAF = 4; % DAF audio playback event
TRIG_KEY = 8; % Key press event (space)
TRIG_ESC = 16; % Escape pressed
TRIG_SET = 32; % Set event
% add break

%% Setup MIDI
haveDAF = isfield(cfg,'DAF_MIDI') && ~isempty(cfg.DAF_MIDI) && ...
          isfield(cfg,'USE_PRESETS') && cfg.USE_PRESETS && ...
          isfield(cfg,'PRESET_MAP') && isa(cfg.PRESET_MAP,'containers.Map');
if ~haveDAF
    warning('DAF_MIDI missing or PRESET_MAP absent — running without DAF (visuals/logging only).');
end

% Define MIDI helper function handles for sending preset recall, engage, and bypass commands
sendSet    = @(ms) midiPreloadPreset(cfg, ms, cmdFH, T);
sendStart  = @()  midiEngage(cfg, cmdFH, T);
sendStop   = @()  midiBypass(cfg, cmdFH, T);

% Check if digital out is present
doDigOut = isfield(cfg,'DIGOUT') && logical(cfg.DIGOUT);

% Turn constant audio playback on
flipState = 0;
if haveDAF && cfg.ALWAYS_ON_0MS
    midiPreloadPreset(cfg, 0, cmdFH, T);   % preload 0 ms preset
    midiEngage(cfg, cmdFH, T);             % engage audio continuously
    flipState = ~flipState;
    log_event(eventFH, doDigOut, T.now(), [], [], 'control', [], TRIG_SET, 'Audio_0ms_Preset_Engaged', flipState);
end

%% Show instructions screen and wait for space keypress or escape abort
instructions = sprintf(['INSTRUCTIONS\n\n' ...
    'When text appears, read it out loud as accurately as possible.\n\n' ...
    'Press SPACE to begin.']);
set(hText,'String',instructions,'FontSize',45,'Color','black'); drawnow;

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

% Send sync beep command to play sync tone on audio output
playSyncBeepLocal();
flipState = ~flipState;
log_event(eventFH, 0, t0, [], [], 'control', [], 0, 'Instructions_End', flipState);

%% Main trial loop
ITI_S = [1.75, 2.25]; % Inter-trial interval range in seconds

for itrial = 1:ntrials
    isCatch = trials.catch_trial(itrial);
    delay_ms_planned = trials.delay(itrial);
    
    % Preload MIDI preset for delay on Eventide H90 before trial begins
    if haveDAF && ~isCatch
        sendSet(delay_ms_planned);
        flipState = ~flipState;
        log_event(eventFH, true, T.now(), [], [], 'control', [], TRIG_SET, sprintf('MIDI_SET_Preset_ms=%d', delay_ms_planned), flipState);
    end

    % ITI + fixation
    if haveDAF && cfg.ALWAYS_ON_0MS
        midiPreloadPreset(cfg, 0, cmdFH, T);   % hold 0 ms between trials
    end
    set(hText,'String','*','Color', tern(~isCatch,[0.7 0.7 0.7],'red'));
    set(hSquare,'FaceColor',[0.3 0.3 0.3]);
    drawnow;
    tFixOn = T.now();
    flipState = ~flipState;
    log_event(eventFH, 0, tFixOn, [], [], tern(isCatch,'catch','speech'), [], TRIG_ITI, 'Fixation_Cross_Onset', flipState);

    % Keep fixation cross on for the randomly sampled ITI duration
    itiDur = ITI_S(1) + rand*(ITI_S(2)-ITI_S(1));
    T.wait(itiDur);

    % After ITI, require spacebar press to continue to next trial
    if cfg.STOP_BETWEEN_TRIALS 
        set(hText,'String','Press SPACE to continue.','Color','black');
        drawnow;  
        while true
            [space, esc] = KeyPoll(hfig); % Handle escape abort
            if esc
                if haveDAF, sendStop(); end
                safeQuit();
                fclose(eventFH); fclose(cmdFH); close(hfig);
                return;
            end
            if space
                break; % Proceed to next trial
            end
            T.wait(0.01);
        end
        set(hText,'String','');
        drawnow;
    end

    % Send DAF ON command relative to fixation onset (if not catch trial)
    if haveDAF && ~isCatch
        if cfg.DAF_START_OFFSET_S ~= 0
            T.until(tFixOn + cfg.DAF_START_OFFSET_S);
        end
        sendStart(); % Sends MIDI commands to engage Eventide delay effect
        flipState = ~flipState;
        log_event(eventFH, doDigOut, T.now(), [], [], 'speech', [], TRIG_DAF, sprintf('DAF_On_cmd(ms=%d)', delay_ms_planned), flipState);
    end

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
            if haveDAF, sendStop(); end
            flipState = ~flipState;
            log_event(eventFH, doDigOut, T.now(), [], [], tern(isCatch,'catch','speech'), [], TRIG_ESC, 'Key_Esc', flipState);
            safeQuit(); fclose(eventFH); fclose(cmdFH); close(hfig); return
        end
        T.wait(0.005);
    end

    % DAF OFF
    if haveDAF && ~isCatch
        midiPreloadPreset(cfg, 0, cmdFH, T); % reset delay to 0 ms preset without stopping audio
        flipState = ~flipState;
        log_event(eventFH, doDigOut, T.now(), [], [], 'speech', [], TRIG_DAF, 'DAF_Off_cmd', flipState);
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
            set(hfig,'WindowKeyPressFcn', @onKey);
            drawnow;
            fprintf('Block %d/%d finished; press spacebar to continue...\n', currentBlock, cfg.n_blocks);
            
            % Change keypress callback to catch space and release uiwait
            set(hfig, 'WindowKeyPressFcn', @(src,evt) ...
                strcmp(evt.Key, 'space') && uiresume(hfig));
            uiwait(hfig);  % Wait for spacebar press
            if ~ishandle(hfig), break; end                 % window closed during break
            set(hfig,'WindowKeyPressFcn', @onKey);         % restore callback safely

            flipState = ~flipState;
            log_event(eventFH, doDigOut, T.now(), [], [], 'control', [], 0, sprintf('Block_%d_Break_End', currentBlock), flipState);
            % Restore original callbacks
            set(hfig,'WindowKeyPressFcn', @onKey);
            set(hText,'String',''); drawnow;
        end
    end
end

%% Cleanup
if haveDAF
    sendStop();
    if isfield(cfg, 'DAF_MIDI') && ~isempty(cfg.DAF_MIDI)
        clear cfg.DAF_MIDI;
    end
end
fclose(eventFH);
fclose(cmdFH);
close(hfig);
fprintf('Task complete.\n');

%% Nested helpers
function out = tern(cond, a, b)
    if cond, out=a; else, out=b; end
end

% Poll keyboard appdata to detect edge-triggered space and escape key events
function [space, esc] = KeyPoll(h)
    if ~ishandle(h), space=false; esc=true; return; end
    space = ~isempty(getappdata(h,'SPACE_FLAG'));
    esc   = ~isempty(getappdata(h,'ESC_FLAG'));
    if space, setappdata(h,'SPACE_FLAG',[]); end
    if esc,   setappdata(h,'ESC_FLAG',[]);   end
end

function safeQuit()
    fprintf('ESC pressed → quitting task\n');
    if isfield(cfg, 'DAF_MIDI') && ~isempty(cfg.DAF_MIDI)
        clear cfg.DAF_MIDI;
    end
end

function playSyncBeepLocal()
    % 50 ms, 1 kHz beep from MATLAB (master-side)
    fs = 44100;
    N  = round(0.05*fs);
    t  = (0:N-1)'/fs;
    y  = 0.5*sin(2*pi*1000*t);
    try sound(y, fs); catch, end
end

function sendMidiCommand(cfg, cmdFH, T, cmdType, varargin)
% Helper for robust MIDI communication
% Sends one of two types of MIDI messages ('programchange' or 'controlchange')
% with up to 3 retry attempts if sending fails (for reliability).
%
% Inputs:
%   cfg     - Configuration struct containing MIDI device handle and settings.
%   cmdFH   - File handle for the command log file (to log MIDI events).
%   T       - Timing struct with function handle T.now() for current time.
%   cmdType - String specifying MIDI command type: 'programchange' or 'controlchange'.
%   varargin- Additional parameters depending on cmdType:
%               For 'programchange': varargin{1} is the preset number (integer).
%               For 'controlchange': varargin{1} is control change number (CC#),
%                                   varargin{2} is control value (0-127).
%
% Outputs:
%   None (side effects: sends MIDI message, logs command)
%
% Usage:
%   Called by midiPreloadPreset, midiEngage, midiBypass to send MIDI instructions
%   reliably to the Eventide H90 device. Ensures commands are sent, with retries
%   upon transient communication failure.
%
    maxRetries = 3;     % Max times to attempt sending MIDI command
    success = false;    % Flag to track if command was sent successfully
    attempt = 0;        % Retry counter
    while ~success && attempt < maxRetries
        attempt = attempt + 1;
        try
            switch lower(cmdType)
                case 'programchange'
                    % Send program change message selecting a preset number
                    % varargin{1} = preset number
                    pn = varargin{1};
                    if iscell(pn), pn = pn{1}; end
                    pn = double(pn);
                    midisend(cfg.DAF_MIDI, 'programchange', cfg.MIDI_CHANNEL, pn);
                case 'controlchange'
                    % Send control change message to modify device parameter
                    % varargin{1} = control change number (CC #)
                    % varargin{2} = control value (0-127)
                    cc = double(varargin{1});
                    vv = double(varargin{2});
                    midisend(cfg.DAF_MIDI, 'controlchange', cfg.MIDI_CHANNEL, cc, vv);
                otherwise
                    error('Unknown MIDI command type: %s', cmdType);
            end
            success = true;  % Command sent successfully, exit retry loop
        catch
            pause(0.1);  % Short delay before retrying on error
        end
    end
    
    % Create a string representation of the MIDI command arguments for logging
    if isempty(varargin)
        argsStr = "";
    else
        % convert varargin (which may contain doubles/chars) into a string array
        argsStr = string(varargin);          % 1xN string array
    end
    argstr = strjoin(argsStr, ',');
    fprintf(cmdFH, '%.6f\t%s\t%s\t\t%d\t%s\n', T.now(), upper(cmdType), char(argstr), attempt-1, 'sendMidiCommand');
    
    % Warn if the command failed after all retries
    if ~success
        warning('Failed to send MIDI command %s after %d attempts.', cmdType, maxRetries);
    end
end

function midiPreloadPreset(cfg, delay_ms, cmdFH, T)
% Preload the MIDI preset corresponding to a requested delay by sending a program change.
%
% Inputs:
%   cfg        - Configuration struct with MIDI info and preset map.
%   delay_ms   - Desired delay in milliseconds (numeric scalar).
%   cmdFH      - File handle for logging MIDI commands.
%   T          - Timing struct with T.now() for timestamp.
%
% Output:
%   None (side effects: sends MIDI program change to load delay preset)
%
% Usage:
%   Called before each trial to set delay time by switching the Eventide preset.
%   If no MIDI device is present, it logs the preset change for offline debugging.
%
    % Round and convert delay to int32 as keys for map lookup
    key = int32(round(delay_ms));
    
    % Offline mode: no MIDI device, just log the intended change
    if ~isfield(cfg, 'DAF_MIDI') || isempty(cfg.DAF_MIDI)
        fprintf('[DAF-OFFLINE] SET %d\n', key);
        fprintf(cmdFH, '%.6f\tSET\t%d\t%s\t%d\t%s\n', T.now(), key, "NA", 0, 'no_midi');
        return;
    end
    
    % Lookup preset number for given delay key
    if isKey(cfg.PRESET_MAP, key)
        pn = cfg.PRESET_MAP(key);
    else
        % If exact delay not found, choose closest preset available
        keys = cell2mat(cfg.PRESET_MAP.keys);  % int32 array of keys
        [~, ix] = min(abs(double(keys) - double(key)));
        pn = cfg.PRESET_MAP(keys(ix));
    end
    
    % Send the program change MIDI command to load the preset
    sendMidiCommand(cfg, cmdFH, T, 'programchange', pn);
end

function midiEngage(cfg, cmdFH, T)
% Sends MIDI control changes to engage (turn on) the delay effect on the Eventide hardware.
%
% Inputs:
%   cfg    - Configuration struct containing MIDI device and mapping info.
%   cmdFH  - File handle for tone command logging.
%   T      - Timing struct with timestamp function T.now().
%
% Output:
%   None (sends MIDI control changes; logs commands)
%
% Usage:
%   Called at the start of a trial where delay effect should be engaged (audio delay effect ON).
%   Typically sends control change to mix wet signal and disable bypass.
%
    % Offline mode: log engage command if no MIDI device present
    if ~isfield(cfg, 'DAF_MIDI') || isempty(cfg.DAF_MIDI)
        fprintf('[DAF-OFFLINE] START\n');
        fprintf(cmdFH, '%.6f\tSTART\t\t%s\t%d\t%s\n', T.now(), "NA", 0, 'no_midi');
        return;
    end
    
    % Optional send MIX control change to set wet level to max (127)
    if isfield(cfg, 'MIX_CC') && ~isempty(cfg.MIX_CC) && ~isnan(cfg.MIX_CC)
        sendMidiCommand(cfg, cmdFH, T, 'controlchange', cfg.MIX_CC, 127);
    end
    
    % Optional send BYPASS control change to disable bypass (engage delay)
    if isfield(cfg, 'BYPASS_CC') && ~isempty(cfg.BYPASS_CC) && ~isnan(cfg.BYPASS_CC)
        sendMidiCommand(cfg, cmdFH, T, 'controlchange', cfg.BYPASS_CC, 0);
    end
end

function midiBypass(cfg, cmdFH, T)
% Sends MIDI control changes to bypass (turn off) the delay effect on the Eventide hardware.
%
% Inputs:
%   cfg    - Configuration struct containing MIDI device and settings.
%   cmdFH  - File handle for MIDI command logging.
%   T      - Timing struct for timestamping.
%
% Output:
%   None (sends MIDI control changes to bypass effect; logs commands)
%
% Usage:
%   Called at the end of trials or at task cleanup to disable the delay effect,
%   typically setting mix level to zero and enabling bypass on hardware.
%
    % Offline mode: log bypass command if no MIDI device present
    if ~isfield(cfg, 'DAF_MIDI') || isempty(cfg.DAF_MIDI)
        fprintf('[DAF-OFFLINE] STOP\n');
        fprintf(cmdFH, '%.6f\tSTOP\t\t%s\t%d\t%s\n', T.now(), "NA", 0, 'no_midi');
        return;
    end
    
    % Optional send MIX control change to set wet level to zero
    if isfield(cfg, 'MIX_CC') && ~isempty(cfg.MIX_CC) && ~isnan(cfg.MIX_CC)
        sendMidiCommand(cfg, cmdFH, T, 'controlchange', cfg.MIX_CC, 0);
    end
    
    % Optional send BYPASS control change to enable bypass (disable effect)
    if isfield(cfg, 'BYPASS_CC') && ~isempty(cfg.BYPASS_CC) && ~isnan(cfg.BYPASS_CC)
        sendMidiCommand(cfg, cmdFH, T, 'controlchange', cfg.BYPASS_CC, 127);
    end
end

end