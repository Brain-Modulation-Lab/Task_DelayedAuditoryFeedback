function test_task(cfg)
% Non-PTB DAF task using MATLAB/Audio Toolbox only.
% Includes: top-left photodiode flash driven by flipSyncState,
% fixed 900x600 window, cfg-provided audio devices,
% fractional-sample delays, vfd.reset(), "End_Message",
% and wrapped text from create_trials_table.

%%%% run delayed auditory feedback task; in or out of operating room
% by Sam Hansen (SH), Andrew Meier (AM); adapted from other Brain Modulation Lab (BML) scripts

%% Task specific parameters
% Fixation Cross ITI parameters
ITI_S = [1.75, 2.25]; % duration range in seconds of ITI

% Trigger codes for event marking
TRIG_ITI    = 1; % Trigger for start of ITI
TRIG_VISUAL = 2; % Visual stimulus onset/offset
TRIG_DAF    = 4; % Delayed auditory feedback on/off
TRIG_KEY    = 8; % Keyboard escape key press

%% Trial table (wrapped text included)
[cfg, trials, text_wrapped_all] = create_trials_table(cfg);

% preallocate non PTB table sections
trials.visual_onset_time = nan(height(trials),1);
trials.visual_off_time  = nan(height(trials),1);
trials.fix_time         = nan(height(trials),1);

%% Initializing log files
eventFile = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n'); % BIDS event file

% Flip-sync state used both for logs and photodiode flash
flipSyncState = 0;

%% Hardware/setup banner
fprintf('Initializing (non-PTB) at %s for subject %s, %s task, session %s, run %i\n\n', ...
    datestr(now,'HH:mm:ss'), cfg.SUBJECT, cfg.TASK, cfg.SESSION_LABEL, cfg.RUN_ID);

%% --- MATLAB-only timing helpers (replace PTB GetSecs/WaitSecs) ---
t0 = tic;                         % reference start for monotonic time
now_secs = @() toc(t0);           % seconds since start (double)
sleep_s  = @(s) pause(max(s,0));  % simple sleep in seconds

%% Audio setup (Audio Toolbox) — use cfg devices (no prompts)
% Hostname only if you want to branch behavior; kept here but unused
if ispc
    [~,host] = system('hostname'); host = deblank(host);
elseif ismac
    [~,host] = system('scutil --get LocalHostName'); host = deblank(host);
else
    host = '';
end

% Resolve devices: LOCAL_TEST only affects which hardware to use
inDev  = cfg.AUDIO_DEVICE_IN;
outDev = cfg.AUDIO_DEVICE_OUT;

% --- Reader (input) ---
reader = audioDeviceReader( ...
    'Device',          cfg.AUDIO_DEVICE_IN, ...
    'SampleRate',      cfg.audio_sample_rate, ...
    'SamplesPerFrame', cfg.audio_frame_size);

% --- Writer (output) ---
writer = audioDeviceWriter( ...
    'Device',     cfg.AUDIO_DEVICE_OUT, ...
    'SampleRate', cfg.audio_sample_rate);

% Determine output channels by probing once
% Prefer stereo; if device is mono, the second write will fail and we fall back
nOut = 2;
try
    setup(writer, zeros(cfg.audio_frame_size, nOut));
catch
    nOut = 1;
    setup(writer, zeros(cfg.audio_frame_size, nOut));
end

% Convenience helpers that always match channel count
toOut  = @(x1) (nOut==1) * x1 + (nOut==2) * [x1 x1];
writeF = @(frame) writer(frame);  % frame is Nx nOut

% Helper to mix any NxC input to Nx1 (mono)
mixMono = @(x) (size(x,2)==1) .* x  +  (size(x,2)>1) .* mean(x, 2);

vfd = dsp.VariableFractionalDelay('InterpolationMethod','Linear', ...
    'MaximumDelay', round(cfg.audio_sample_rate));
setup(vfd, zeros(cfg.audio_frame_size,1), 1); % full init before loop

% Prime audio pipeline
zmono = zeros(cfg.audio_frame_size, 1);
for k = 1:10
    writeF(toOut(zmono));
end

maxDelay_ms    = max(cfg.delay_values_ms);
maxDelayFrames = ceil((maxDelay_ms/1000) * cfg.audio_sample_rate / cfg.audio_frame_size) + 5;

%% Visuals (MATLAB graphics) — fixed-size centered window
screenSize = get(0, 'ScreenSize');
fig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', ...
             'NumberTitle','off', 'Units','pixels', 'Position', [0 0 screenSize(3) screenSize(4)]);
ax = axes('Parent',fig,'Position',[0 0 1 1],'Visible','off');
hText = text(0.5, 0.5, '', 'FontSize', cfg.stim_font_size, 'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','middle','Units','normalized','Parent', ax);

% Photodiode square (top-left, normalized coords)
pdiode_square_length = 0.05;
hSquare = annotation(fig,'rectangle','FaceColor',[1 1 1],'EdgeColor','none', ...
    'Position',[0, 1 - pdiode_square_length, pdiode_square_length, pdiode_square_length]);

set_pdiode(hSquare, 0);

% esc
setappdata(fig, 'escPressed', false);
set(fig, 'WindowKeyPressFcn', @(~,evt) ...
    setappdata(fig,'escPressed', strcmp(evt.Key,'escape')));
goto_cleanup  = false;

%% Instructions and sync beeps (PTB-free)
instructions = ['INSTRUCTIONS\n\n' ...
    'When text appears on the screen,\n' ...
    'read as quickly and accurately as possible.\n\n' ...
    'Press any key to begin...'];
instrOn = now_secs();

% Press any key to begin
set(hText, 'String', sprintf(instructions), 'FontSize', 55, 'Color', 'black');
figure(fig);
wait_any_key(fig);                      % <- any key resumes; ESC sets escPressed
if getappdata(fig,'escPressed'); goto_cleanup = true; end
set(hText,'String',''); drawnow;

% --- Clear instructions and display SYNC cue ---
set(hText, 'String', ''); drawnow;
set(hText, 'String', 'SYNC', 'FontSize', 48, 'Color', 'red'); drawnow;

% --- SYNC beeps through the same audioDeviceWriter (cross-platform) ---
fs = cfg.audio_sample_rate;
f0 = 1000;        % Hz
dur = 0.20;       % s
gap = 0.3;        % s between beeps
t  = (0:1/fs:dur-1/fs).';
tone = 0.2*sin(2*pi*f0*t);

set(hText, 'String', 'SYNC', 'FontSize', 48, 'Color', 'red'); drawnow;

refTime = NaN;
for i = 1:3
    if i == 1, refTime = now_secs(); end
    sound(tone, fs);
    pause(gap);
end

% Flush writer/VFD with silence
for k=1:8
    writeF(toOut(zmono));
end

% --- Clear screen after final beep ---
set(hText, 'String', ''); drawnow;

% --- Log instruction onset with photodiode flip ---
flipSyncState = ~flipSyncState;
set_pdiode(hSquare, flipSyncState);
log_event(eventFile, 0, instrOn, [], [], [], [], 0, 'Instructions', flipSyncState);

%% Trial Loop main
runStartTime = now_secs();
speechVsCatch = '';
goto_cleanup  = false;

% Lag diagnostics buffer
doSoftLag   = isfield(cfg,'LAG_DIAGNOSTICS') && cfg.LAG_DIAGNOSTICS;
lagBuffer   = zeros(1, 5000);
lagIndex    = 1;
lagCount    = 0;

% scheduled breaks
if ~isfield(cfg,'ntrials_between_breaks') || isempty(cfg.ntrials_between_breaks)
    cfg.ntrials_between_breaks = max(1, round(cfg.ntrials / max(cfg.n_blocks,1)));
end

for itrial = 1:cfg.ntrials
    %  scheduled break check
    if itrial < cfg.ntrials && mod(itrial, cfg.ntrials_between_breaks) == 0
        % mark break for photodiode/log
        flipSyncState = ~flipSyncState;
        set_pdiode(hSquare, flipSyncState);
        log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], [], [], 0, 'Break message', flipSyncState);
    
        % show break screen and wait for ANY key; ESC will set escPressed
        wait_break_any_key(fig, hText);
    
        % abort if ESC was pressed during the break
        if getappdata(fig,'escPressed')
            goto_cleanup = true;
            break;
        end
    end

    % Trial type (catch vs speech)
    if trials.catch_trial(itrial)
        speechVsCatch = 'catch';
        fixColor = 'red';
    else
        speechVsCatch = 'speech';
        fixColor = [0.7 0.7 0.7]; % light gray for cue
    end

    % Fractional-sample delay allowed
    delay_samples = (cfg.audio_sample_rate * trials.delay(itrial) / 1000);

    % Flush audio path a few frames then reset delay
    for iframe = 1:maxDelayFrames
        writer(zeros(cfg.audio_frame_size,1));
        vfd(zeros(cfg.audio_frame_size,1), delay_samples);
    end
    vfd.reset();

    % Diagnostic print
    fprintf('Starting trial %d with stim index %d and delay %d ms\n', ...
        itrial, trials.stim_idx(itrial), trials.delay(itrial));

    % ITI with fixation and log
    set(hText, 'String', '*', 'FontSize', cfg.stim_font_size, 'Color', fixColor);
    drawnow;
    itiFixOnTime = now_secs();
    trials.fix_time(itrial) = itiFixOnTime;

    ItiDuration   = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);
    flipSyncState = ~flipSyncState;
    set_pdiode(hSquare, flipSyncState);
    log_event(eventFile, cfg.DIGOUT, itiFixOnTime, ItiDuration, [], speechVsCatch, [], TRIG_ITI, 'Fixation_Cross_Onset', flipSyncState);

    % ITI wait loop (ESC/Stop responsive)
    tEnd = itiFixOnTime + ItiDuration;
    while now_secs() < tEnd
        if getappdata(fig,'escPressed')
            flipSyncState = ~flipSyncState;
            set_pdiode(hSquare, flipSyncState);
            log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], speechVsCatch, [], TRIG_ITI + TRIG_KEY, 'Escape/Stop', flipSyncState);
            goto_cleanup = true; break;
        end
        sleep_s(0.005);
    end
    if goto_cleanup, break; end

    % Visual stimulus on (wrapped text)
    wrapped_text = text_wrapped_all{trials.stim_idx(itrial)};
    set(hText, 'String', wrapped_text, 'FontSize', cfg.stim_font_size, 'Color', 'black');
    drawnow;
    stimOnsetTime = now_secs();

    flipSyncState = ~flipSyncState;
    set_pdiode(hSquare, flipSyncState);
    trials.visual_onset_time(itrial) = stimOnsetTime;
    text_stim = trials.stim{itrial};
    log_event(eventFile, cfg.DIGOUT, stimOnsetTime, [], [], speechVsCatch, text_stim, TRIG_VISUAL, 'Visual Onset', flipSyncState);

    % Streaming Loop: mic -> fractional delay -> speakers
    if ~trials.catch_trial(itrial)
        trialStart   = now_secs();
        frameCounter = 0;

        while (now_secs() - trialStart) < cfg.text_stim_dur && ~getappdata(fig,'escPressed')

            tStart  = now_secs();
            audioIn = reader();
            audioIn = mixMono(audioIn);  % <- ensure Nx1
            
            delay_samples = cfg.audio_sample_rate * trials.delay(itrial) / 1000;
            delayed = vfd(audioIn, delay_samples);  % Nx1
            
            % BOOST gain (start with ~10 like your old script; tune later)
            g = cfg.audio_playback_gain;  % e.g., set 10–15 in cfg
            audioOut = max(min(g * delayed, 1), -1);  % Nx1
            
            writeF(toOut(audioOut));  % exactly one write per frame

            if doSoftLag
                frameDur_ms = (cfg.audio_frame_size/cfg.audio_sample_rate)*1000;
                lag = max((now_secs() - tStart)*1000 - frameDur_ms, 0);
                lagBuffer(lagIndex) = lag;
                lagIndex = mod(lagIndex, 5000) + 1;
                lagCount = min(lagCount+1, 5000);
            end

            frameCounter = frameCounter + 1;
            if mod(frameCounter, 10) == 0
                drawnow;
            end

            pause(0.001); % tame CPU
        end

        % Tail flush
        tailFrames = ceil((max(cfg.delay_values_ms)/1000) * cfg.audio_sample_rate / cfg.audio_frame_size) + 5;
        for iframe = 1:tailFrames
            y = vfd(zeros(cfg.audio_frame_size,1), delay_samples);  % Nx1
            y = max(min(g * y, 1), -1);
            writeF(toOut(y));
        end
        vfd.reset();
        sleep_s(0.1);
    else
        % Catch or local test: passive wait, ESC/Stop responsive
        t0_local = now_secs();
        while (now_secs() - t0_local) < cfg.text_stim_dur
            if getappdata(fig,'escPressed')
                goto_cleanup = true; break;
            end
            sleep_s(0.005);
        end
        if goto_cleanup, break; end
    end

    % DAF off event (speech trials only)
    if ~trials.catch_trial(itrial)
        flipSyncState = ~flipSyncState;
        set_pdiode(hSquare, flipSyncState);
        dafOffTime = now_secs();
        log_event(eventFile, cfg.DIGOUT, dafOffTime, [], [], speechVsCatch, [], TRIG_DAF, 'DAF Off', flipSyncState);
    end

    % Visual off
    set(hText, 'String', ''); drawnow;
    flipSyncState = ~flipSyncState;
    set_pdiode(hSquare, flipSyncState);
    visOffTime = now_secs();
    trials.visual_off_time(itrial) = visOffTime;
    log_event(eventFile, cfg.DIGOUT, visOffTime, [], [], speechVsCatch, [], TRIG_VISUAL, 'Visual Off', flipSyncState);

    % Progress print
    elapsed = now_secs() - runStartTime;
    fprintf('Trial %2i / %i completed at %02d:%02d \n', itrial, cfg.ntrials, floor(elapsed/60), round(mod(elapsed,60)));

    % Persist trial row
    if itrial == 1
        writetable(trials(1,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteVariableNames', true);
    else
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteMode', 'append', 'WriteVariableNames', false);
    end
end

%% Cleanup section (+ final event)
flipSyncState = ~flipSyncState;
set_pdiode(hSquare, flipSyncState);
log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], [], [], 0, 'End_Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n', ...
    cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));
fprintf('RUN ID: %i\n',cfg.RUN_ID);

% Release hardware, close windows
try release(reader);  catch, end
try release(writer);  catch, end
try release(vfd);     catch, end
try close(fig);       catch, end
try fclose(eventFile);catch, end

end % function test_task

%% Helper function (Ternary operator: returns a if cond is true, else b)
function out = ifelse(cond, a, b)
    if cond, out = a; else, out = b; end
end

%% Photodiode helper (white = on, black = off)
function set_pdiode(h, on)
    if on, set(h,'FaceColor',[1 1 1]); else, set(h,'FaceColor',[0 0 0]); end
end

%%
function localWriteChunked(x, writerFn, F)
    % x is NxC with C fixed (1 or 2), F is frame size
    N = size(x,1); C = size(x,2);
    i = 1;
    while i <= N
        j = min(i+F-1, N);
        frame = x(i:j, :);
        if size(frame,1) < F
            frame(F, C) = 0; % pad
        end
        writerFn(frame);
        i = j + 1;
    end
end

function wait_break_any_key(fig, hText)
% Show break text and wait for ANY key; ESC sets 'escPressed' and exits.
    if ~ishghandle(fig), return; end
    set(hText,'String','Take a break!\n\nPress any key to continue.','Color','black');
    drawnow;
    wait_any_key(fig); % resumes on any key; ESC sets 'escPressed'
    if ishghandle(fig) && ~getappdata(fig,'escPressed')
        set(hText,'String',''); drawnow;
    end
end

function wait_any_key(fig)
% Block until ANY key is pressed on 'fig'. ESC sets 'escPressed' and still resumes.
    if ~ishghandle(fig), return; end
    oldCb = get(fig,'WindowKeyPressFcn');
    set(fig,'WindowKeyPressFcn', @(~,evt) local_on_any_key(fig, evt));
    try, uiwait(fig); catch, end
    if ishghandle(fig), set(fig,'WindowKeyPressFcn', oldCb); end
end

function local_on_any_key(fig, evt)
% During waits: mark ESC, then resume UI.
    try
        if isfield(evt,'Key') && strcmp(evt.Key,'escape')
            if ishghandle(fig), setappdata(fig,'escPressed', true); end
        end
    catch
    end
    try uiresume(fig); catch, end
end