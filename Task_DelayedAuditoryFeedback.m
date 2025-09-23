function Task_DelayedAuditoryFeedback(cfg)
%% Task specific parameters
% Fixation Cross ITI parameters
ITI_S = [1.75, 2.25]; % duration range in seconds of ITI

% Trigger codes for event marking
TRIG_ITI = 1; % Trigger for start of ITI
TRIG_VISUAL = 2; % Visual stimulus onset/offset
TRIG_DAF = 4; % Delayed auditory feedback on/off
TRIG_KEY = 8; % Keyboard escape key pres

%% Make trial table
% Load list of stimulus sentences as cell array for presentation
sentPath = fullfile(cfg.PATH_TASK,'stimuli',cfg.daf_sentences);
lines = readlines(sentPath);
lines = strip(lines); % trim spaces
lines(lines == "") = []; % drop empty rows
sentences = cellstr(lines);

% Number of unique sentences and delay conditions
nSentences = numel(sentences);
nDelays = numel(cfg.delayOptions);

% Generate all sentence-delay pairs, then shuffle with constraints 
allSentences = repmat((1:nSentences)', nDelays, 1);
allDelays = reshape(repmat(cfg.delayOptions, nSentences, 1), [], 1);
perm = randperm(length(allSentences));

shuffledSentences = allSentences(perm);
shuffledDelays = allDelays(perm);

% Ensure consecutive repeated sentences are swapped to avoid repeats
for i = 2:numel(shuffledSentences)
    if shuffledSentences(i) == shuffledSentences(i-1)
        j = i + find(shuffledSentences(i+1:end) ~= shuffledSentences(i), 1, 'first');
        if ~isempty(j), j = j; else, j = i; end
        % swap i and j
        tmpS = shuffledSentences(i); shuffledSentences(i) = shuffledSentences(j); shuffledSentences(j) = tmpS;
        tmpD = shuffledDelays(i);    shuffledDelays(i)    = shuffledDelays(j);    shuffledDelays(j)    = tmpD;
    end
end

% Further shuffle while avoiding back-to-back repeats
finalSentences = shuffledSentences;
finalDelays = shuffledDelays;
used = false(size(shuffledSentences));
finalSentences(1) = shuffledSentences(1);
finalDelays(1) = shuffledDelays(1);
used(1) = true;
for i = 2:length(shuffledSentences)
    candidates = find(~used & shuffledSentences ~= finalSentences(i-1));
    if isempty(candidates)
        candidates = find(~used); % allow repeats only if no alternative
    end
    nextIdx = candidates(randi(numel(candidates)));
    finalSentences(i) = shuffledSentences(nextIdx);
    finalDelays(i) = shuffledDelays(nextIdx);
    used(nextIdx) = true;
end

% Calculate total planned trials for all blocks with optional max-trial capping
blockNtrials = length(finalSentences);
nTrials = cfg.n_blocks * blockNtrials;
if isfield(cfg,'max_trials') && ~isempty(cfg.max_trials)
    nTrials = min(nTrials, cfg.max_trials);
end

% Initialize indexing arrays for trial parameters
trialSentIdx = zeros(nTrials,1);
trialDelays = zeros(nTrials,1);
trialBlock = zeros(nTrials,1);
trialCounter = 1;
for b = 1:cfg.n_blocks
    thisBlockN = min(blockNtrials, nTrials - trialCounter + 1);
    if thisBlockN <= 0
        break;
    end
    idx = trialCounter:(trialCounter + thisBlockN - 1);
    trialSentIdx(idx) = finalSentences(1:thisBlockN);
    trialDelays(idx) = finalDelays(1:thisBlockN);
    trialBlock(idx) = b;
    trialCounter = trialCounter + thisBlockN;
end

% Catch trial vector
nCatch = round(nTrials * cfg.catchRatio);
catchVec = false(nTrials,1);
if nCatch > 0
    catchVec(randperm(nTrials, nCatch)) = true;
end

% Pre wrap every sentence once
text_wrapped_all = cell(nSentences,1);
nl = sprintf('\n');
for si = 1:nSentences
    text_stim = regexprep(sentences{si}, '\r', '');
    if isfield(cfg,'stim_max_char_per_line') && ~isempty(cfg.stim_max_char_per_line) && cfg.stim_max_char_per_line>0
        w = split(string(text_stim));
        cur = ""; lines = strings(0,1);
        for ii = 1:numel(w)
            nxt = strtrim(cur + " " + w(ii));
            if strlength(nxt) <= cfg.stim_max_char_per_line
                cur = nxt;
            else
                if strlength(cur)>0, lines(end+1) = cur; end
                cur = w(ii);
            end
        end
        if strlength(cur)>0, lines(end+1) = cur; end
        text_wrapped_all{si} = char(strjoin(lines, nl));
    else
        text_wrapped_all{si} = char(text_stim);
    end
end

% Trial table
DAF_Trials = table( ...
    (1:nTrials).', ...
    trialBlock(:), ...
    sentences(trialSentIdx), ...
    trialSentIdx(:), ...
    trialDelays(:), ...
    catchVec(:), ...
    'VariableNames', {'trialnum','block_id','sentence','sentence_idx','delay','catch'} ...
);

% Initialize additional columns where timing info will be saved during the experiment
DAF_Trials.start_time = NaT(nTrials,1,'TimeZone','local');
DAF_Trials.visual_onset_time = NaT(nTrials,1,'TimeZone','local');
DAF_Trials.visual_off_time = NaT(nTrials,1,'TimeZone','local');
DAF_Trials.lag_mean = nan(nTrials,1);
cfg.TRIAL_TABLE = DAF_Trials;

%% Initializing log files
eventFile = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n'); %BIDS event file in system time coord

%% Hardware setup
fprintf('Initializing psychtoolbox at %s for subject %s, %s task, session %s, run %i\n\n', ...
    datestr(now,'HH:mm:ss'), cfg.SUBJECT, cfg.TASK, cfg.SESSION_LABEL, cfg.RUN_ID);

% Initialize Keyboard
fprintf('Initializing Keyboard...'); 
if isempty(cfg.KEYBOARD_ID)
    fprintf('\nNo keyboard selected, using default. Choose KEYBOARD_ID from this table:\n'); 
    if ~cfg.LOCAL_TEST
        devices = struct2table(PsychHID('Devices'));
    else
        % Simulate or set dummy device info for local test
        devices = table();
        fprintf('Skipping PsychHID device enumeration for local test mode.\n');
    end
    disp(devices);
end

% Initialize Psychtoolbox sound with low latency
InitializePsychSound(1);

% Audio device selection and opening for full duplex playback and recording
if ~cfg.LOCAL_TEST
    pa_tbl = struct2table(PsychPortAudio('GetDevices'));
    % Select output and input devices based on Host API and user configura
    apiMask = contains(pa_tbl.HostAudioAPIName, cfg.HOST_AUDIO_API_NAME, 'IgnoreCase', true);
    outMask = apiMask & pa_tbl.NrOutputChannels > 0;
    if isfield(cfg,'AUDIO_DEVICE') && ~isempty(cfg.AUDIO_DEVICE)
        outMask = outMask & contains(pa_tbl.DeviceName, cfg.AUDIO_DEVICE, 'IgnoreCase', true);
    end
    if ~any(outMask)
        disp(pa_tbl); error('No OUTPUT device matched HostAPI "%s".', cfg.HOST_AUDIO_API_NAME);
    end
    [~, io] = max(pa_tbl.NrOutputChannels(outMask));
    outIdx = find(outMask);
    outIdx = outIdx(io);
    cfg.AUDIO_ID = pa_tbl.DeviceIndex(outIdx);
    pa_channels = min(2, pa_tbl.NrOutputChannels(outIdx));

    % Input selection
    inMask = apiMask & pa_tbl.NrInputChannels > 0;
    if isfield(cfg,'AUDIO_DEVICE_IN') && ~isempty(cfg.AUDIO_DEVICE_IN)
        inMask = inMask & contains(pa_tbl.DeviceName, cfg.AUDIO_DEVICE_IN, 'IgnoreCase', true);
    end
    if ~any(inMask)
        disp(pa_tbl); error('No INPUT device matched HostAPI "%s".', cfg.HOST_AUDIO_API_NAME);
    end
    [~, ii] = max(pa_tbl.NrInputChannels(inMask));
    inIdx = find(inMask);
    inIdx = inIdx(ii);
    cfg.AUDIO_IN_ID = pa_tbl.DeviceIndex(inIdx);

    % Open audio devices: master playback, recorder, and slave for output routing
    pa_mode = 1 + 8; % playback + master
    pa_reqlatencyclass = 3; % robust low-latency
    cfg.pa_master = PsychPortAudio('Open', cfg.AUDIO_ID, pa_mode, pa_reqlatencyclass, [], pa_channels);
    statusMaster = PsychPortAudio('GetStatus', cfg.pa_master);
    Fs = statusMaster.SampleRate;
    fprintf('Using hardware sample rate: %d Hz\n', Fs);

    % Recorder & slave with same Fs
    cfg.pa_rec = PsychPortAudio('Open', cfg.AUDIO_IN_ID, 2, pa_reqlatencyclass, Fs, 1);
    cfg.pa_slave3 = PsychPortAudio('OpenSlave', cfg.pa_master, 1, pa_channels);

    % Prime device buffers and start audio streams
    PsychPortAudio('GetAudioData', cfg.pa_rec, 10);
    PsychPortAudio('Start', cfg.pa_master, 0, 0, 0);
    WaitSecs(0.02);
    PsychPortAudio('Start', cfg.pa_rec, 0, 0, 0);
else
    % Local test mode: skip hardware setup and use default parameters
    fprintf('LOCAL_TEST: skipping audio setup\n');
    Fs = 48000;
    cfg.pa_master = [];
    cfg.pa_rec = [];
    cfg.pa_slave3 = [];
end

% Compute delay times in audio samples from milliseconds, store in map
uniqueDelaysMs = unique(round(cfg.delayOptions(:)));
delayMsToSamples = containers.Map('KeyType','int32','ValueType','double');
for k = 1:numel(uniqueDelaysMs)
    delayMsToSamples(int32(uniqueDelaysMs(k))) = Fs * (uniqueDelaysMs(k)/1000);
end

% Map trial delay ms to samples (double precision for accuracy)
trialDelaySamples = zeros(nTrials,1,'double');
for i = 1:nTrials
    trialDelaySamples(i) = delayMsToSamples(int32(round(DAF_Trials.delay(i))));
end

% Configure max delay for fractional delay filter and create filter instance
maxDelaySamples = max(ceil(max(trialDelaySamples)), round(0.25 * Fs) );
vfd = dsp.VariableFractionalDelay('MaximumDelay', maxDelaySamples);

% Default background color if not specified, normalized just before window open
if ~isfield(cfg,'bg_color')
    cfg.bg_color = [255 255 255];
end

% Normalize color
if max(cfg.bg_color) > 1
    cfg.bg_color = double(cfg.bg_color)./255;
end

% Get the largest screen number (usually the main display)
scr = max(Screen('Screens'));

% Open Psychtoolbox screen window, fullscreen or windowed depending on mode
if cfg.LOCAL_TEST
    % Tell PTB to create a real GUI window instead of fullscreen
    PsychImaging('PrepareConfiguration');
    PsychImaging('AddTask', 'General', 'UseGUIWindow');
    debugWindowWidth = 1024;
    debugWindowHeight = 640;
    sr = Screen('Rect', scr);
    cx = (sr(3)-debugWindowWidth)/2;
    cy = (sr(4)-debugWindowHeight)/2;
    windowRect = [cx, cy, cx+debugWindowWidth, cy+debugWindowHeight];
    [window, ~] = PsychImaging('OpenWindow', scr, cfg.bg_color, windowRect);
    fprintf('Opened PTB LOCAL_TEST in a real desktop window (%dx%d, resizable/movable)\n', ...
            debugWindowWidth, debugWindowHeight);
else
    % Standard fullscreen mode
    [window, ~] = PsychImaging('OpenWindow', scr, cfg.bg_color);
end

% Set alpha blending for smooth text and stimuli
Screen('BlendFunction', window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
Screen('TextSize', window, cfg.stim_font_size);

% Build an offscreen texture for each wrapped sentence
sentTex = nan(nSentences,1);
textColor = [0 0 0];
for si = 1:nSentences
    off = Screen('OpenOffscreenWindow', window, cfg.bg_color);
    Screen('TextSize', off, cfg.stim_font_size); 
    DrawFormattedText(off, text_wrapped_all{si}, 'center', 'center', textColor);
    sentTex(si) = off;
end

% Calculate fixation cross coordinates and properties for drawing
[winW, winH] = Screen('WindowSize', window);
[cx, cy] = RectCenter([0 0 winW winH]);
arm = 40;
lw = 5;
xy = [ cx-arm, cx+arm, cx, cx;
    cy, cy, cy-arm, cy+arm ];

% Set up keyboard escape key identification and priority
KbName('UnifyKeyNames');
ESC = KbName('ESCAPE');
device = []; % default keyboard

if ~cfg.LOCAL_TEST
    Priority(MaxPriority(window)); % raise MATLAB priority for experiment timing
else
    Priority(0); % normal priority for debug mode
end

% Enable keyboard listening without echoing characters to command window
ListenChar(0);
ShowCursor;

%% ******************************************************************** %%
%                         TASK SPECIFIC SECTION                          %
%  ********************************************************************  %

fprintf('%s Task run is starting...\n', cfg.TASK);
fprintf('\nStarting run %i at %s \n',cfg.RUN_ID,datestr(now,'HH:MM:SS am'));
fprintf('RUN ID: %i\n\n',cfg.RUN_ID);

%% Display instructions screen and wait for keypress to start
instr = 'INSTRUCTIONS\n\nWhen text appears on the screen,\n Read as quickly and accurately as possible.\n\nPress any key to begin...';
Screen('FillRect', window, cfg.bg_color);
DrawFormattedText(window, instr, 'center', 'center', [0 0 0]);
[instrOn, ~] = Screen('Flip', window);
KbReleaseWait(device); % swallow any prior keypress
[~, keyCode] = KbStrokeWait(device); % blocks until a key is pressed

goto_cleanup = keyCode(ESC) > 0; % exit if ESC pressed here
if goto_cleanup
    if ~cfg.LOCAL_TEST
        try PsychPortAudio('Stop',  cfg.pa_slave3, 1, 1); catch, end
        try PsychPortAudio('Stop',  cfg.pa_rec,    1, 1); catch, end
        try PsychPortAudio('Stop',  cfg.pa_master, 1, 1); catch, end
        try PsychPortAudio('Close', cfg.pa_slave3);       catch, end
        try PsychPortAudio('Close', cfg.pa_rec);          catch, end
        try PsychPortAudio('Close', cfg.pa_master);       catch, end
    end
    try Screen('CloseAll'); catch, end
    try fclose(eventFile);  catch, end
    try KbQueueRelease;     catch, end
    try Priority(0);        catch, end
    try ListenChar(0);      catch, end
    try ShowCursor;         catch, end
    return
end

% Initialize keyboard queue for low-latency key detection during task
KbQueueCreate(device);
KbQueueStart(device); 

% Initialize clocks for event timin
baseGetSecs = GetSecs();
baseClock = datetime('now','TimeZone','local');

% Log instruction onset using flip timestamp
flipSyncState = 0;
flipSyncState = ~flipSyncState;
log_event(eventFile, 0, instrOn, [], [], [], [], 0, 'Instructions', flipSyncState);

%% Trial Loop main
runStartTime = GetSecs();
trialType = '';
blockFrames = 4;
frameSamples = cfg.audio_frame_size;
blockSamples = blockFrames * frameSamples;
streamBufStereo = zeros(2, blockSamples, 'double');
goto_cleanup = false;

% Check if lag diagnostics enabled
doSoftLag = isfield(cfg,'LAG_DIAGNOSTICS') && cfg.LAG_DIAGNOSTICS && ~cfg.LOCAL_TEST;

for idxTrial = 1:nTrials
    % Check for user abort with ESC key
    [isDown, ~, kc] = KbQueueCheck(device);
    if isDown && kc(ESC)
        flipSyncState = ~flipSyncState;
        code = TRIG_KEY;
        log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], trialType, [], code, 'Escape/Stop', flipSyncState);
        goto_cleanup = true; break;
    end

    % Determine if trial is catch (no speech) or speech trial
    isSpeak = ~DAF_Trials.catch(idxTrial);
    if DAF_Trials.catch(idxTrial)
        trialType = 'catch';
    else
        trialType = 'speech';
    end
    fixColor = [0 0 0];
    if ~isSpeak
        fixColor = [255 0 0];
    end

    delay_samples = trialDelaySamples(idxTrial);
        
    % Display diagnostic info about trial start
    fprintf('Starting trial %d with sentence index %d and delay %d ms\n', idxTrial, DAF_Trials.sentence_idx(idxTrial), DAF_Trials.delay(idxTrial));

    % ITI with fixation cross display and log
    Screen('FillRect', window, cfg.bg_color);
    Screen('DrawLines', window, xy, lw, fixColor);
    flipSyncState = ~flipSyncState;
    [itiFixOnTime, ~] = Screen('Flip', window);
    DAF_Trials.start_time(idxTrial) = baseClock + seconds(itiFixOnTime - baseGetSecs);
    
    ItiDuration = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);
    code = TRIG_ITI;
    log_event(eventFile, cfg.DIGOUT, itiFixOnTime, ItiDuration, [], trialType, [], code, 'Trial Onset', flipSyncState);
    
    % ITI wait loop with abort check loop
    tEnd = itiFixOnTime + ItiDuration;
    while GetSecs < tEnd
        [isDown, ~, kc] = KbQueueCheck(device);
        if isDown && kc(ESC)
            flipSyncState = ~flipSyncState;
            log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], trialType, [], TRIG_ITI + TRIG_KEY, 'Escape/Stop', flipSyncState);
            goto_cleanup = true;
            break
        end
    end
    WaitSecs(0.005);
    if goto_cleanup, break; end

    % Pre sentence blank screen followed by configured delay before stimulus
    Screen('FillRect', window, cfg.bg_color);
    Screen('Flip', window);
    WaitSecs(cfg.delay_dur);

    % DAF audio playback start (for speech trials, non-local mode only)
    if isSpeak && ~cfg.LOCAL_TEST
        % Prefill silence to give the slave FIFO some headroom:
        prefill = zeros(pa_channels, round(0.25 * Fs), 'double');
        PsychPortAudio('FillBuffer', cfg.pa_slave3, prefill);
        reset(vfd);
        PsychPortAudio('Start', cfg.pa_slave3, 0, 0, 0);
        flipSyncState = ~flipSyncState;
        code = TRIG_DAF;
        dafTriggerTime = GetSecs();
        log_event(eventFile, cfg.DIGOUT, dafTriggerTime, [], [], trialType, [], code, 'DAF On', flipSyncState);
    end

    % Visual stimulus on: draw text texture and flip screen
    Screen('FillRect', window, cfg.bg_color);
    Screen('DrawTexture', window, sentTex(DAF_Trials.sentence_idx(idxTrial)));
    flipSyncState = ~flipSyncState;
    [stimOnsetTime, ~] = Screen('Flip', window);
    DAF_Trials.visual_onset_time(idxTrial) = baseClock + seconds(stimOnsetTime - baseGetSecs);
    code = TRIG_VISUAL;
    text_stim = sentences{DAF_Trials.sentence_idx(idxTrial)};
    log_event(eventFile, cfg.DIGOUT, stimOnsetTime, [], [], trialType, text_stim, code, 'Visual Onset', flipSyncState);

    % Streaming Loop: read microphone audio, apply delay, output delayed audio
    if isSpeak && ~cfg.LOCAL_TEST
        KbQueueFlush(device);
        trialStart = GetSecs();
        if doSoftLag
            lagSum = 0; 
            lagN   = 0;
        end
        while (GetSecs - trialStart) < cfg.text_stim_dur
            % ESC abort check in streaming loop
            [pressed, fp] = KbQueueCheck(device);
            if pressed && fp(ESC) > 0
                flipSyncState = ~flipSyncState;
                log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], trialType, [], TRIG_KEY, 'Escape/Stop', flipSyncState);
                goto_cleanup = true;
                break
            end
    
            % Non-blocking audio input read with max length blockSamples
            [a, tCapFirst, ~] = PsychPortAudio('GetAudioData', cfg.pa_rec, [], 0, 0, 1);

            % Mix stereo to mono if needed, zero pad or truncate
            if ~isempty(a)
                if size(a,1) > 1, a = mean(a,1); end % mixdown to mono
                a = a(:);
            else
                a = single([]); % keep type stable
            end
            n = numel(a);
            if n < blockSamples
                a = [a; zeros(blockSamples-n,1,'single')];
            elseif n > blockSamples
                a = a(end-blockSamples+1:end);
            end

            % Apply configured fractional delay to input audio block
            delayed = vfd(single(a), single(delay_samples));
            y = double(delayed(:)).' * cfg.audio_playback_gain;
            y = max(min(y, 1), -1);
            
            % Optional soft lag diagnostics tracking delay performance
            if doSoftLag && ~isempty(tCapFirst) && n > 0
                tCapLast = tCapFirst + (min(n, blockSamples)-1)/Fs; % timestamp for last captured sample in this block
                tEnq = GetSecs();
                extra_s = (tEnq - tCapLast) - double(delay_samples)/Fs; % extra over requested delay
                if extra_s > 0
                    lagSum = lagSum + extra_s;
                    lagN = lagN + 1;
                end
            end

            % Fill output buffers for either stereo or mono output
            if pa_channels >= 2
                streamBufStereo(1,:) = y;
                streamBufStereo(2,:) = y;
                PsychPortAudio('FillBuffer', cfg.pa_slave3, streamBufStereo, 1); % streaming refill
            else
                PsychPortAudio('FillBuffer', cfg.pa_slave3, y, 1);
            end
        end

        % Save mean lag time in milliseconds for trial, or NaN if none measured
        if doSoftLag && lagN > 0
            DAF_Trials.lag_mean(idxTrial) = 1000 * (lagSum / lagN);
        else
            DAF_Trials.lag_mean(idxTrial) = NaN;
        end

        if goto_cleanup, break; end
    else
        % For catch or local test mode, simple pause loop with key abort check
        t0 = GetSecs();
        while (GetSecs - t0) < cfg.text_stim_dur
            [isDown, ~, kc] = KbQueueCheck(device);
            if isDown && kc(ESC)
                flipSyncState = ~flipSyncState;
                log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], trialType, [], TRIG_KEY, 'Escape/Stop', flipSyncState);
                goto_cleanup = true;
                break
            end
            WaitSecs(0.005);
        end
    end

    % DAF off
    if isSpeak && ~cfg.LOCAL_TEST
        PsychPortAudio('Stop', cfg.pa_slave3, 0, 0);
        flipSyncState = ~flipSyncState;
        dafOffTime = GetSecs();
        code = TRIG_DAF;
        log_event(eventFile, cfg.DIGOUT, dafOffTime, [], [], trialType, [], code, 'DAF Off', flipSyncState);
    end

    % Visual off
    Screen('FillRect', window, cfg.bg_color);
    flipSyncState = ~flipSyncState;
    [visOffTime, ~] = Screen('Flip', window);
    DAF_Trials.visual_off_time(idxTrial) = baseClock + seconds(visOffTime - baseGetSecs);
    code = TRIG_VISUAL;
    log_event(eventFile, cfg.DIGOUT, visOffTime, [], [], trialType, [], code, 'Visual Off', flipSyncState);

    % Display trial completion summary
    elapsed = GetSecs() - runStartTime;
    fprintf('Trial %2i / %i completed at %02d:%02d \n', idxTrial, nTrials, floor(elapsed/60), round(mod(elapsed,60)));

    % Save current trial data to disk; write headers only on first occasion
    if idxTrial == 1
        writetable(DAF_Trials(1,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteVariableNames', true);
    else
        writetable(DAF_Trials(idxTrial,:), cfg.TRIAL_FILENAME, 'Delimiter', '\t', 'FileType', 'text', 'WriteMode', 'append', 'WriteVariableNames', false);
    end
end

%% Cleanup section: log final event and safely close resources
flipSyncState = ~flipSyncState;
log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], [], [], 0, 'End Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n', ...
    cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datestr(now,'HH:MM:SS'));
fprintf('RUN ID: %i\n',cfg.RUN_ID);

% Stop and close audio devices
if ~cfg.LOCAL_TEST
    try PsychPortAudio('Stop',  cfg.pa_rec,    1, 1); catch, end
    try PsychPortAudio('Stop',  cfg.pa_master, 1, 1); catch, end
    try PsychPortAudio('Stop',  cfg.pa_slave3, 1, 1); catch, end
    try PsychPortAudio('Close', cfg.pa_slave3);       catch, end
    try PsychPortAudio('Close', cfg.pa_rec);          catch, end
    try PsychPortAudio('Close', cfg.pa_master);       catch, end
end

% Close offscreen text windows
for si = 1:numel(sentTex)
    if ~isnan(sentTex(si)), Screen('Close', sentTex(si)); end
end

% Release keyboard queue, reset priority and listeners, close screen
try KbQueueRelease(device); catch, end
try ListenChar(0);          catch, end
try ShowCursor;             catch, end
try Priority(0);            catch, end
try Screen('CloseAll');     catch, end

% Close the event file safely
try fclose(eventFile);      catch, end