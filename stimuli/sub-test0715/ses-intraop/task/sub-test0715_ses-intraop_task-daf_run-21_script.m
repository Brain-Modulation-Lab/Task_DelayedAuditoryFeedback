function test_task(cfg)
% Non-PTB DAF task using MATLAB/Audio Toolbox only.
% Includes: top-left photodiode flash (flipSyncState),
% fixed 900x600 window, cfg-provided audio devices,
% fractional-sample delays, vfd.reset(), "End_Message",
% and wrapped text from create_trials_table.

%% Task specific parameters
ITI_S = [1.75, 2.25]; % ITI range (s)

% Trigger codes
TRIG_ITI    = 1;
TRIG_VISUAL = 2;
TRIG_DAF    = 4;
TRIG_KEY    = 8;

%% Trial table (wrapped text included)
[cfg, trials, text_wrapped_all] = create_trials_table(cfg);

%% Init log
eventFile = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n');

flipSyncState = 0;

fprintf('Initializing (non-PTB) at %s for subject %s, %s task, session %s, run %i\n\n', ...
    datestr(now,'HH:mm:ss'), cfg.SUBJECT, cfg.TASK, cfg.SESSION_LABEL, cfg.RUN_ID);

%% Simple timing helpers
t0 = tic;
now_secs = @() toc(t0);
sleep_s  = @(s) pause(max(s,0));

%% --- Headset guard (optional) ---
% If your selected devices look like Bluetooth headsets, prefer 48 kHz and larger frames.
if contains(lower(string(cfg.AUDIO_DEVICE_IN)), {'headset','bluetooth'}) || ...
   contains(lower(string(cfg.AUDIO_DEVICE_OUT)),{'headset','bluetooth'})
    if ~isfield(cfg,'audio_sample_rate') || cfg.audio_sample_rate ~= 48000
        cfg.audio_sample_rate = 48000;
    end
    if ~isfield(cfg,'audio_frame_size') || cfg.audio_frame_size < 240
        cfg.audio_frame_size = 240;
    end
end

%% Audio I/O (reader/writer) built from cfg
readerArgs = {'Device', cfg.AUDIO_DEVICE_IN, ...
              'SampleRate', cfg.audio_sample_rate, ...
              'SamplesPerFrame', cfg.audio_frame_size};
if isfield(cfg,'AUDIO_DRIVER') && ~isempty(cfg.AUDIO_DRIVER)
    readerArgs(end+1:end+2) = {'Driver', cfg.AUDIO_DRIVER}; % e.g., 'ASIO' on Windows rig
end
reader = audioDeviceReader(readerArgs{:});

writerArgs = {'Device', cfg.AUDIO_DEVICE_OUT, 'SampleRate', cfg.audio_sample_rate};
if isfield(cfg,'AUDIO_DRIVER_OUT') && ~isempty(cfg.AUDIO_DRIVER_OUT)
    writerArgs(end+1:end+2) = {'Driver', cfg.AUDIO_DRIVER_OUT};
end
writer = audioDeviceWriter(writerArgs{:});

% Fix output channel count once; always honor this shape
nOut = 2;
try
    setup(writer, zeros(cfg.audio_frame_size, nOut));
catch
    nOut = 1;
    setup(writer, zeros(cfg.audio_frame_size, nOut));
end
toOut  = @(mono) (nOut==1)*mono(:) + (nOut==2)*[mono(:) mono(:)];
writeF = @(frame) writer(frame); % frame must be Nx nOut

% Delay line
vfd = dsp.VariableFractionalDelay('MaximumDelay', round(cfg.audio_sample_rate));

% Prime with silence (no mic→speaker)
zmono = zeros(cfg.audio_frame_size, 1);
for k = 1:10
    writeF(toOut(zmono));
    vfd(zeros(cfg.audio_frame_size,1), 0);
end

maxDelay_ms    = max(cfg.delay_values_ms);
maxDelayFrames = ceil((maxDelay_ms/1000) * cfg.audio_sample_rate / cfg.audio_frame_size) + 5;

%% Visuals — fixed-size centered window + photodiode
screenSize = get(0, 'ScreenSize');
figW = 900; figH = 600;
figL = (screenSize(3)-figW)/2; figB = (screenSize(4)-figH)/2;
fig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', ...
             'Position',[figL figB figW figH],'NumberTitle','off');
ax = axes('Parent',fig,'Position',[0 0 1 1],'Visible','off');
hText = text(0.5, 0.5, '', 'FontSize', cfg.stim_font_size, 'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','middle','Units','normalized','Parent', ax);

pdiode_square_length = 0.05; % 5% figure height/width
hSquare = annotation(fig,'rectangle','FaceColor',[1 1 1],'EdgeColor','none', ...
    'Position',[0, 1 - pdiode_square_length, pdiode_square_length, pdiode_square_length]);
set_pdiode(hSquare, flipSyncState);

% Stop window + ESC
stopFig = figure('Name','Stop','NumberTitle','off','MenuBar','none','ToolBar','none','Position',[300 100 200 80]);
setappdata(0, 'stopReq', false);
uicontrol(stopFig,'Style','pushbutton','String','Stop','FontSize',14,'Position',[50 20 100 40], ...
    'Callback', @(~,~) setappdata(0,'stopReq',true));
setappdata(fig, 'escPressed', false);
set(fig, 'WindowKeyPressFcn', @(~,evt) setappdata(fig,'escPressed', strcmp(evt.Key,'escape')));

%% Instructions + SYNC beeps (same writer/samplerate)
instructions = ['INSTRUCTIONS\n\n' ...
    'When text appears on the screen,\n' ...
    'read as quickly and accurately as possible.\n\n' ...
    'Press any key to begin...'];

set(hText, 'String', sprintf(instructions), 'FontSize', 55, 'Color', 'black');
figure(fig);
instrOn = now_secs();

prevHandler = get(fig, 'WindowKeyPressFcn');
set(fig, 'WindowKeyPressFcn', @(~,~) uiresume(fig));
uiwait(fig);
set(fig, 'WindowKeyPressFcn', prevHandler);

set(hText, 'String', ''); drawnow;
set(hText, 'String', 'SYNC', 'FontSize', 48, 'Color', 'red'); drawnow;

% Beeps at the SAME fs as writer
fs   = cfg.audio_sample_rate;
f0   = 1000;
dur  = 0.20;
gap  = 0.30;
ramp = 0.005;

t    = (0:1/fs:dur-1/fs)';
tone = sin(2*pi*f0*t);
nR   = max(1, round(ramp*fs));
env  = ones(size(tone));
env(1:nR)         = 0.5 - 0.5*cos(pi*(0:nR-1)'/(nR-1));
env(end-nR+1:end) = flipud(env(1:nR));
tone = 0.2 * (tone .* env);

playChunked = @(x) localWriteChunked(toOut(x), writeF, cfg.audio_frame_size);

refTime = NaN;
for i=1:3
    if i==1, refTime = now_secs(); end
    playChunked(tone);
    pause(gap);
end

% Flush with silence
for k=1:8, writeF(toOut(zmono)); end

% --- One-time I/O sanity check (1 s direct monitor) ---
p = reader(); 
rmsP = sqrt(mean(double(p).^2));
fprintf('Mic RMS (speak now): %.6f\n', rmsP);
tEnd = now_secs() + 1.0;
while now_secs() < tEnd
    x = reader();
    y = max(min(0.2 * x, 1), -1);
    writeF(toOut(y));
end

% Clear screen
set(hText, 'String', ''); drawnow;

% Timing base
baseGetSecs = refTime;
baseClock   = datetime('now','TimeZone','local');

% Log instruction onset + photodiode flip
flipSyncState = ~flipSyncState;
set_pdiode(hSquare, flipSyncState);
log_event(eventFile, 0, instrOn, [], [], [], [], 0, 'Instructions', flipSyncState);

%% Trial loop
runStartTime = now_secs();
speechVsCatch = '';
goto_cleanup  = false;

doSoftLag   = isfield(cfg,'LAG_DIAGNOSTICS') && cfg.LAG_DIAGNOSTICS;
lagBuffer   = zeros(1, 5000);
lagIndex    = 1;
lagCount    = 0;

for itrial = 1:cfg.ntrials
    if getappdata(fig,'escPressed')
        flipSyncState = ~flipSyncState; set_pdiode(hSquare, flipSyncState);
        log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], speechVsCatch, [], TRIG_KEY, 'Escape/Stop', flipSyncState);
        goto_cleanup = true; break;
    end
    if getappdata(0,'stopReq')
        flipSyncState = ~flipSyncState; set_pdiode(hSquare, flipSyncState);
        log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], speechVsCatch, [], TRIG_KEY, 'Stop Button', flipSyncState);
        goto_cleanup = true; break;
    end

    if trials.catch_trial(itrial)
        speechVsCatch = 'catch';
        fixColor = 'red';
    else
        speechVsCatch = 'speech';
        fixColor = [0.7 0.7 0.7];
    end

    delay_samples = (cfg.audio_sample_rate * trials.delay(itrial) / 1000);

    % Flush a few frames, then reset delay line
    for iframe = 1:maxDelayFrames
        writeF(toOut(zmono));
        vfd(zeros(cfg.audio_frame_size,1), delay_samples);
    end
    vfd.reset();

    fprintf('Starting trial %d with stim index %d and delay %d ms\n', ...
        itrial, trials.stim_idx(itrial), trials.delay(itrial));

    % ITI + log
    set(hText, 'String', '*', 'FontSize', cfg.stim_font_size, 'Color', fixColor);
    drawnow;
    itiFixOnTime = now_secs();
    trials.fix_time(itrial) = baseClock + seconds(itiFixOnTime - baseGetSecs);

    ItiDuration   = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);
    flipSyncState = ~flipSyncState; set_pdiode(hSquare, flipSyncState);
    log_event(eventFile, cfg.DIGOUT, itiFixOnTime, ItiDuration, [], speechVsCatch, [], TRIG_ITI, 'Fixation_Cross_Onset', flipSyncState);

    tEnd = itiFixOnTime + ItiDuration;
    while now_secs() < tEnd
        if getappdata(fig,'escPressed') || getappdata(0,'stopReq')
            flipSyncState = ~flipSyncState; set_pdiode(hSquare, flipSyncState);
            log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], speechVsCatch, [], TRIG_ITI + TRIG_KEY, 'AbortDuringITI', flipSyncState);
            goto_cleanup = true; break;
        end
        sleep_s(0.005);
    end
    if goto_cleanup, break; end

    % Pre-stim delay
    sleep_s(cfg.delay_dur);

    % Visual ON (wrapped)
    wrapped_text = text_wrapped_all{trials.stim_idx(itrial)};
    set(hText, 'String', wrapped_text, 'FontSize', cfg.stim_font_size, 'Color', 'black');
    drawnow;
    stimOnsetTime = now_secs();

    flipSyncState = ~flipSyncState; set_pdiode(hSquare, flipSyncState);
    trials.visual_onset_time(itrial) = baseClock + seconds(stimOnsetTime - baseGetSecs);
    text_stim = trials.stim{itrial};
    log_event(eventFile, cfg.DIGOUT, stimOnsetTime, [], [], speechVsCatch, text_stim, TRIG_VISUAL, 'Visual Onset', flipSyncState);

    % --- DAF streaming ---
    if ~trials.catch_trial(itrial)
        trialStart   = now_secs();
        frameCounter = 0;

        while (now_secs() - trialStart) < cfg.text_stim_dur && ...
              ~getappdata(0,'stopReq') && ~getappdata(fig,'escPressed')

            tStart  = now_secs();
            audioIn = reader();                      % Nx1
            delayed = vfd(audioIn, delay_samples);   % Nx1 (fractional ok)
            audioOut= max(min(cfg.audio_playback_gain * delayed, 1), -1);
            writeF(toOut(audioOut));                 % ALWAYS Nx nOut

            if doSoftLag
                frameDur_ms = (cfg.audio_frame_size/cfg.audio_sample_rate)*1000;
                lag = max((now_secs() - tStart)*1000 - frameDur_ms, 0);
                lagBuffer(lagIndex) = lag;
                lagIndex = mod(lagIndex, 5000) + 1;
                lagCount = min(lagCount+1, 5000);
            end

            frameCounter = frameCounter + 1;
            if mod(frameCounter, 10) == 0, drawnow; end
            pause(0.001);
        end

        % Tail flush from delay line
        for iframe = 1:maxDelayFrames
            audioOut = vfd(zeros(cfg.audio_frame_size,1), delay_samples);
            audioOut = max(min(cfg.audio_playback_gain * audioOut, 1), -1);
            writeF(toOut(audioOut));
        end
        vfd.reset();
        sleep_s(0.1);
    else
        % Catch: passive wait
        t0_local = now_secs();
        while (now_secs() - t0_local) < cfg.text_stim_dur
            if getappdata(fig,'escPressed') || getappdata(0,'stopReq')
                goto_cleanup = true; break;
            end
            sleep_s(0.005);
        end
        if goto_cleanup, break; end
    end

    % DAF off event
    if ~trials.catch_trial(itrial)
        flipSyncState = ~flipSyncState; set_pdiode(hSquare, flipSyncState);
        dafOffTime = now_secs();
        log_event(eventFile, cfg.DIGOUT, dafOffTime, [], [], speechVsCatch, [], TRIG_DAF, 'DAF Off', flipSyncState);
    end

    % Visual OFF
    set(hText, 'String', ''); drawnow;
    flipSyncState = ~flipSyncState; set_pdiode(hSquare, flipSyncState);
    visOffTime = now_secs();
    trials.visual_off_time(itrial) = baseClock + seconds(visOffTime - baseGetSecs);
    log_event(eventFile, cfg.DIGOUT, visOffTime, [], [], speechVsCatch, [], TRIG_VISUAL, 'Visual Off', flipSyncState);

    % Progress
    elapsed = now_secs() - runStartTime;
    fprintf('Trial %2i / %i completed at %02d:%02d \n', itrial, cfg.ntrials, floor(elapsed/60), round(mod(elapsed,60)));

    % Persist trial row
    if itrial == 1
        writetable(trials(1,:), cfg.TRIAL_FILENAME, 'Delimiter','\t','FileType','text','WriteVariableNames', true);
    else
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter','\t','FileType','text','WriteMode','append','WriteVariableNames', false);
    end
end

%% Cleanup
flipSyncState = ~flipSyncState; set_pdiode(hSquare, flipSyncState);
log_event(eventFile, cfg.DIGOUT, now_secs(), [], [], [], [], 0, 'End_Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n', ...
    cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));
fprintf('RUN ID: %i\n',cfg.RUN_ID);

try release(reader);  catch, end
try release(writer);  catch, end
try release(vfd);     catch, end
try close(fig);       catch, end
try close(stopFig);   catch, end
try fclose(eventFile);catch, end
rmappdata(0,'stopReq');

end % test_task

%% Helpers
function set_pdiode(h, on)
    if on, set(h,'FaceColor',[1 1 1]); else, set(h,'FaceColor',[0 0 0]); end
end

function localWriteChunked(x, writerFn, F)
    % x: NxC, fixed C (1 or 2); write in F-sized blocks
    N = size(x,1); C = size(x,2);
    i = 1;
    while i <= N
        j = min(i+F-1, N);
        frame = x(i:j, :);
        if size(frame,1) < F, frame(F, C) = 0; end
        writerFn(frame);
        i = j + 1;
    end
end