function task_daf_ptb(cfg)
% Audio engine: PTB uses a single full-duplex PsychPortAudio stream; task_daf uses audioDeviceReader + audioDeviceWriter (+ dsp.VariableFractionalDelay).
% Delay method: PTB = simple integer-sample circular buffer; task_daf = fractional delay filter each frame.
% 0-ms trials: PTB bypasses audio entirely at 0 ms; task_daf still runs through the audio path.
% Device usage: PTB uses one device for in/out; task_daf may use different devices for input vs output.
% Buffering: PTB drip-feeds small steady chunks with a brief prime; task_daf primes by reading+writing multiple frames and flushes more heavily per trial.
% Beeps: PTB plays beeps through the same PTB device; task_daf uses sound() (OS default device).
% Hot-loop work: PTB keeps the loop lean (no pause, minimal UI); task_daf computes per-frame lag, calls drawnow, and includes pause(0.001).
% Visuals: Both use MATLAB figures (PTB Screen(...) in task_daf is commented out).

%% Task params (unchanged)
ITI_S = [1.75, 2.25];
TRIG_ITI   = 1;
TRIG_VISUAL= 2;
TRIG_DAF   = 4;
TRIG_KEY   = 8;

%% Trial table
[cfg, trials] = create_trials_table(cfg);

%% Init logs
eventFile = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n');

fprintf('Initializing PTB (audio) at %s for subject %s, %s task, session %s, run %i\n\n', ...
    datestr(now,'HH:mm:ss'), cfg.SUBJECT, cfg.TASK, cfg.SESSION_LABEL, cfg.RUN_ID);

%% Keyboard
KbName('UnifyKeyNames');
ESC = KbName('ESCAPE');
device = [];
ListenChar(0);
ShowCursor;
KbQueueCreate(device);
KbQueueStart(device);

%% Visuals: keep MATLAB figure UI (unchanged)
screenSize = get(0, 'ScreenSize');
fig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', ...
             'Position',[screenSize(3)/4 screenSize(4)/4 900 600],'NumberTitle','off');
ax = axes('Parent',fig,'Position',[0 0 1 1],'Visible','off');
hText = text(0.5, 0.5, '', 'FontSize', cfg.stim_font_size, 'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','middle','Units','normalized','Parent',ax);
stopFig = figure('Name','Stop','NumberTitle','off','MenuBar','none','ToolBar','none','Position',[300 100 200 80]);
setappdata(0, 'stopReq', false);
uicontrol(stopFig,'Style','pushbutton','String','Stop','FontSize',14,'Position',[50 20 100 40], ...
    'Callback', @(~,~) setappdata(0,'stopReq',true));

%% Instructions screen
instructions = ['INSTRUCTIONS\n\n' ...
    'When text appears on the screen,\n'...
    'Read as quickly and accurately as possible.\n\n' ...
    'Press any key to begin...'];
set(hText, 'String', sprintf(instructions), 'FontSize', 55, 'Color','black');
figure(fig);
instrOn = GetSecs();
set(fig, 'WindowKeyPressFcn', @(~,~) uiresume(fig));
uiwait(fig);
set(fig, 'WindowKeyPressFcn', '');
set(hText, 'String', ''); drawnow;

%% PTB Audio setup (NEW)
InitializePsychSound(1); % request low-latency scheduling

% Preferred sample rate (unchanged: do not alter hardware configuration)
if isfield(cfg,'audio_sample_rate') && ~isempty(cfg.audio_sample_rate)
    freq = cfg.audio_sample_rate;
else
    freq = 48000; % safe default for many interfaces
end

% Choose ONE full-duplex device (prefer ASIO on Windows)
devs = PsychPortAudio('GetDevices');
idx = [];
if isfield(cfg,'AUDIO_DEVICE_HINT') && ~isempty(cfg.AUDIO_DEVICE_HINT)
    % Try to match by name or API first
    hit = find(contains({devs.DeviceName}, cfg.AUDIO_DEVICE_HINT, 'IgnoreCase', true) & ...
               [devs.NrInputChannels] > 0 & [devs.NrOutputChannels] > 0, 1);
    if ~isempty(hit), idx = hit; end
end
if isempty(idx)
    % Prefer ASIO full-duplex if present
    isASIO = contains({devs.HostAudioAPIName}, 'ASIO', 'IgnoreCase', true);
    cand = find(isASIO & [devs.NrInputChannels] > 0 & [devs.NrOutputChannels] > 0, 1);
    if ~isempty(cand)
        idx = cand;
    else
        % Otherwise first full-duplex device
        idx = find([devs.NrInputChannels] > 0 & [devs.NrOutputChannels] > 0, 1);
    end
end
assert(~isempty(idx), 'No full-duplex PTB audio device found.');

reqlatencyclass = 1;        % start moderate; tighten later
buffersize      = 512;      % conservative
suggestedLatency= 0.025;    % ~25 ms safety
mode = 3;                   % full-duplex

pah = PsychPortAudio('Open', devs(idx).DeviceIndex, mode, reqlatencyclass, freq, ...
                     max(devs(idx).NrInputChannels, devs(idx).NrOutputChannels), ...
                     buffersize, suggestedLatency);

% Start stream and give PTB a recording buffer
PsychPortAudio('GetAudioData', pah, 10); % 10s internal capture buffer
PsychPortAudio('Start', pah, 0, 0, 1);

% Beep via PTB (no OS sound())
beepWave = 0.1 * sin(2*pi*1000*(0:1/freq:0.2)); % 200 ms @ 1kHz
PsychPortAudio('FillBuffer', pah, [beepWave; beepWave], 0);  % queue once
WaitSecs(0.1);
PsychPortAudio('FillBuffer', pah, [beepWave; beepWave], 0);  % twice more
WaitSecs(0.1);
PsychPortAudio('FillBuffer', pah, [beepWave; beepWave], 0);

%% Timing refs & initial event log
KbQueueFlush(device);
baseGetSecs = GetSecs();
baseClock   = datetime('now','TimeZone','local');
flipSyncState = 0;
flipSyncState = ~flipSyncState;
log_event(eventFile, cfg.DIGOUT, instrOn, [], [], [], [], 0, 'Instructions', flipSyncState);

%% Streaming parameters (PTB)
framesPerChunk = 256;   % ~5.3 ms at 48k; try 128–256
playGain       =  cfg.audio_playback_gain; if isempty(playGain), playGain = 1.0; end
outch          = 2;     % duplicate mono to stereo

% Prime playback with brief silence
PsychPortAudio('FillBuffer', pah, zeros(outch, framesPerChunk));

%% Trial loop
runStartTime = GetSecs();
goto_cleanup = false;
for itrial = 1:cfg.ntrials
    % Abort check
    [isDown, ~, kc] = KbQueueCheck(device);
    if isDown && kc(ESC)
        flipSyncState = ~flipSyncState;
        log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], [], [], TRIG_KEY, 'Escape/Stop', flipSyncState);
        goto_cleanup = true; break;
    end

    isCatch = trials.catch_trial(itrial);
    set(hText, 'String', '*', 'FontSize', cfg.stim_font_size, 'Color', tern(~isCatch, [0.7 0.7 0.7], 'red'));
    drawnow;
    itiFixOnTime = GetSecs;
    trials.fix_time(itrial) = baseClock + seconds(itiFixOnTime - baseGetSecs);

    flipSyncState = ~flipSyncState;
    ItiDuration = ITI_S(1) + (ITI_S(2)-ITI_S(1))*rand(1);
    log_event(eventFile, cfg.DIGOUT, itiFixOnTime, ItiDuration, [], tern(isCatch,'catch','speech'), [], TRIG_ITI, 'Fixation_Cross_Onset', flipSyncState);

    tEnd = itiFixOnTime + ItiDuration;
    while GetSecs < tEnd
        [isDown, ~, kc] = KbQueueCheck(device);
        if isDown && kc(ESC)
            flipSyncState = ~flipSyncState;
            log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], tern(isCatch,'catch','speech'), [], TRIG_ITI+TRIG_KEY, 'Escape/Stop', flipSyncState);
            goto_cleanup = true; break;
        end
        WaitSecs(0.003);
    end
    if goto_cleanup, break; end

    WaitSecs(cfg.delay_dur);

    % Visual onset
    set(hText, 'String', trials.stim{itrial}, 'FontSize', cfg.stim_font_size, 'Color','black'); drawnow;
    stimOnsetTime = GetSecs();
    flipSyncState = ~flipSyncState;
    log_event(eventFile, cfg.DIGOUT, stimOnsetTime, [], [], tern(isCatch,'catch','speech'), trials.stim{itrial}, TRIG_VISUAL, 'Visual Onset', flipSyncState);

    % === PTB audio streaming for this trial ===
    if ~isCatch && ~cfg.LOCAL_TEST
        % Build circular delay for this trial (integer samples)
        delay_ms   = trials.delay(itrial);
        delay_samp = max(0, round(delay_ms/1000 * freq));

        if delay_samp == 0
            % When DAF is off (0 ms), bypass audio routing entirely (no capture/play)
            t0 = GetSecs;
            while (GetSecs - t0) < cfg.text_stim_dur && ~getappdata(0,'stopReq')
                % passive wait
            end
        else
            rb_len     = delay_samp + round(0.100*freq); % 100 ms headroom
            ring       = zeros(1, rb_len);
            wptr       = 1; rptr = mod(wptr-1 - delay_samp, rb_len) + 1;

            trialStart = GetSecs;
            while (GetSecs - trialStart) < cfg.text_stim_dur && ~getappdata(0,'stopReq')
                % Non-blocking capture of ~framesPerChunk samples
                [inChunk, ~, ovfl] = PsychPortAudio('GetAudioData', pah, framesPerChunk/freq); %#ok<ASGLU>
                if isempty(inChunk)
                    in = zeros(1, framesPerChunk);
                else
                    if size(inChunk,1) > 1, inChunk = mean(inChunk,1); end % mono
                    in = inChunk(1,:);
                    if numel(in) < framesPerChunk
                        in(end+1:framesPerChunk) = 0;
                    elseif numel(in) > framesPerChunk
                        in = in(end-framesPerChunk+1:end);
                    end
                end

                % Write into ring
                idx = wptr + (0:framesPerChunk-1); idx = mod(idx-1, rb_len) + 1; ring(idx) = in;
                wptr = mod(wptr-1 + framesPerChunk, rb_len) + 1;

                % Read delayed
                ridx = rptr + (0:framesPerChunk-1); ridx = mod(ridx-1, rb_len) + 1; out = ring(ridx);
                rptr = mod(rptr-1 + framesPerChunk, rb_len) + 1;

                % Output drip-feed (stereo)
                y = max(min(playGain * out, 1), -1);
                y2 = [y; y];
                PsychPortAudio('FillBuffer', pah, y2, 1); % append
            end
        end

        flipSyncState = ~flipSyncState;
        log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], 'speech', [], TRIG_DAF, 'DAF Off', flipSyncState);
        % brief tail silence to flush FIFO
        PsychPortAudio('FillBuffer', pah, zeros(outch, framesPerChunk));
        WaitSecs(0.05);
    else
        % catch/local: passive wait with abort check
        t0 = GetSecs();
        while (GetSecs - t0) < cfg.text_stim_dur
            [isDown, ~, kc] = KbQueueCheck(device);
            if isDown && kc(ESC)
                flipSyncState = ~flipSyncState;
                log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], tern(isCatch,'catch','speech'), [], TRIG_KEY, 'Escape/Stop', flipSyncState);
                goto_cleanup = true; break;
            end
            WaitSecs(0.003);
        end
    end

    % Visual off
    set(hText, 'String',''); drawnow;
    visOffTime = GetSecs();
    flipSyncState = ~flipSyncState;
    log_event(eventFile, cfg.DIGOUT, visOffTime, [], [], tern(isCatch,'catch','speech'), [], TRIG_VISUAL, 'Visual Off', flipSyncState);

    % Progress
    elapsed = GetSecs() - runStartTime;
    fprintf('Trial %2i / %i completed at %02d:%02d \n', itrial, cfg.ntrials, floor(elapsed/60), round(mod(elapsed,60)));

    % Save trial row
    if itrial == 1
        writetable(trials(1,:), cfg.TRIAL_FILENAME, 'Delimiter','\t','FileType','text','WriteVariableNames',true);
    else
        writetable(trials(itrial,:), cfg.TRIAL_FILENAME, 'Delimiter','\t','FileType','text','WriteMode','append','WriteVariableNames',false);
    end

    if goto_cleanup, break; end
end

%% Cleanup
flipSyncState = ~flipSyncState;
log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], [], [], 0, 'End Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n', cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));

try PsychPortAudio('Stop',  pah, 1); catch, end
try PsychPortAudio('Close', pah);     catch, end

try KbQueueRelease(device); catch, end
try ListenChar(0);          catch, end
try ShowCursor;             catch, end
try Priority(0);            catch, end
try fclose(eventFile);      catch, end
try close(fig);             catch, end
try close(stopFig);         catch, end

end

function out = tern(cond, a, b)
    if cond, out = a; else, out = b; end
end