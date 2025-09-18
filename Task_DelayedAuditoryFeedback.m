function Task_DelayedAuditoryFeedback(cfg)
%% Task specific parameters
    
% Fixation Cross ITI parameters
ITI_S = [1.75, 2.25]; % duration range in seconds of ITI

%% trigger codes
TRIG_ITI = 1; %%%% send this when stim is removed at end of trial
TRIG_VISUAL = 2;
TRIG_TRIAL = 4; %%% send this before fix cross at beginning of trial
TRIG_DAF = 8;
TRIG_KEY = 16; %%% send this 

% Load sentences (one per line, no header) 
T = readtable(fullfile(cfg.PATH_TASK,'stimuli',cfg.DAF_SENTENCES_TSV), ...
              'FileType','text','Delimiter','\t','ReadVariableNames',false);
sentences = T.Var1;
nSentences = numel(sentences);

[sIdxGrid, dIdxGrid] = ndgrid(1:nSentences, 1:numel(cfg.delayOptions));
blockSentIdx  = sIdxGrid(:);
blockDelays   = cfg.delayOptions(dIdxGrid(:));
blockNtrials  = numel(blockSentIdx);
nTrials       = cfg.n_blocks * blockNtrials;

trialSentIdx = zeros(nTrials,1);
trialDelays  = zeros(nTrials,1);
trialBlock   = zeros(nTrials,1);
trialCounter = 1;
for b = 1:cfg.n_blocks
    perm = randperm(blockNtrials);
    idx  = trialCounter:(trialCounter + blockNtrials - 1);
    trialSentIdx(idx) = blockSentIdx(perm);
    trialDelays(idx)  = blockDelays(perm);
    trialBlock(idx)   = b;
    trialCounter      = trialCounter + blockNtrials;
end

nCatch = round(nTrials * cfg.catchRatio);
catchVec = false(nTrials,1);
if nCatch > 0
    catchVec(randperm(nTrials, nCatch)) = true;
end

DAF_Trials = table( ...
    (1:nTrials).', ...
    trialBlock(:), ...
    sentences(trialSentIdx), ...
    trialSentIdx(:), ...
    trialDelays(:), ...
    catchVec(:), ...
    'VariableNames', {'trialnum','block_id','sentence','sentence_idx','delay','catch'} ...
);

DAF_Trials.start_time         = NaT(nTrials,1);
DAF_Trials.visual_onset_time  = NaT(nTrials,1);
DAF_Trials.visual_off_time    = NaT(nTrials,1);

cfg.TRIAL_TABLE = DAF_Trials;

%% warnings and cleanup functions
onCleanupTasks = cell(20,1); %creating cleanup cell array container to enforce cleanup order

%% Initializing log files

%opening events file
eventFile = fopen(cfg.EVENT_FILENAME, 'a');  % Appending mode
onCleanupTasks{19} = onCleanup(@() fclose(eventFile));
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n'); %BIDS event file in system time coord

%% Initializing psychtoolbox
fprintf('Initializing psychtoolbox at %s for subject %s, %s task, session %s, run %i\n\n',datestr(now,'HH:MM:SS'),cfg.SUBJECT,cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID);

% Initializing Keyboard
fprintf('Initializing Keyboard...'); 
if isempty(cfg.KEYBOARD_ID)
    fprintf('\nNo keyboard selected, using default. Choose KEYBOARD_ID from this table:\n'); 
    % Detect keyboards attached to system
    devices = struct2table(PsychHID('Devices'));  
    disp(devices);
end

KbName('UnifyKeyNames')
keyCodeEscape = KbName('ESCAPE');
fprintf('done\n'); 

% getting audio device id
pa_devices = struct2table(PsychPortAudio('GetDevices'));
pa_devices_sel = contains(pa_devices.HostAudioAPIName,cfg.HOST_AUDIO_API_NAME) & contains(pa_devices.DeviceName,cfg.AUDIO_DEVICE); 
if sum(pa_devices_sel) == 0 
    disp(pa_devices);
    error('%s - %s not found. Choose one from the list of available audio devices',cfg.HOST_AUDIO_API_NAME,cfg.AUDIO_DEVICE);
elseif sum(pa_devices_sel) > 1
    disp(pa_devices);
    error('%s - %s matches more than one device. Choose one from the list of available audio devices',cfg.HOST_AUDIO_API_NAME,cfg.AUDIO_DEVICE);
else
    fprintf('The following audio device was selected:\n');
    disp(pa_devices(pa_devices_sel,:));
    cfg.AUDIO_ID = pa_devices.DeviceIndex(pa_devices_sel);
end
pa_mode = 1+8; %1 == sound playback only; 8 == opening as 'master' device
pa_reqlatencyclass = 1; % Try to get the lowest latency that is possible under the constraint of reliable playback.  
pa_freq = []; %loading default freq for device
pa_channels = 2; %playing as stereo, converting to mono by hardware connector
pa_master = PsychPortAudio('Open', cfg.AUDIO_ID, pa_mode, pa_reqlatencyclass, pa_freq, pa_channels);
pa_rec = PsychPortAudio('Open', [], 2, pa_reqlatencyclass, [], 1); % 2 = record
PsychPortAudio('GetAudioData', pa_rec, 10);
PsychPortAudio('Start', pa_rec, 0, 0, 1);

% Delay calculation in samples
uniqueDelaysMs = round(unique(cfg.delayOptions(:)));
delaySamplesVec = cfg.audio_sample_rate * (uniqueDelaysMs / 1000);
maxDelaySamples = ceil(max(delaySamplesVec)) + 5;
vfd = dsp.VariableFractionalDelay('MaximumDelay', maxDelaySamples);
delayLUT = containers.Map('KeyType','int32','ValueType','double');
for k = 1:numel(uniqueDelaysMs)
    delayLUT(int32(uniqueDelaysMs(k))) = delaySamplesVec(k);
end

% loading audio and verifying output frequency and resampling
pa_master_status = PsychPortAudio('GetStatus', pa_master);
pa_Fs = pa_master_status.SampleRate;
onCleanupTasks{18} = onCleanup(@() PsychPortAudio('Close', pa_master));

% starting master device
pa_repetitions = 0;
pa_when = 0;
pa_waitForStart = 0;
PsychPortAudio('Start', pa_master, pa_repetitions, pa_when, pa_waitForStart);
onCleanupTasks{17} = onCleanup(@() PsychPortAudio('Stop', pa_master));

flipSyncState=0;

maxDelayFrames = ceil((max(cfg.delayOptions)/1000) * cfg.audio_sample_rate / cfg.audio_frame_size) + 5;

if ~isfield(cfg,'bg_color'), cfg.bg_color = [255 255 255]; end
scr = max(Screen('Screens'));
PsychDefaultSetup(2);
[window, ~] = PsychImaging('OpenWindow', scr, cfg.bg_color);
Screen('TextSize', window, cfg.stim_font_size);


%% ******************************************************************** %%
%                         TASK SPECIFIC SECTION                          %
%  ********************************************************************  %
%% 
fprintf('%s Task run is starting...\n', cfg.TASK);

% creating slave audio channel for sentences
pa_slave3 = PsychPortAudio('OpenSlave', pa_master, pa_mode, pa_channels);
onCleanupTasks{7} = onCleanup(@() PsychPortAudio('Close', pa_slave3));
onCleanupTasks{6} = onCleanup(@() fprintf('Cleaning up.\n'));

fprintf('\nPress any key to advance trial. \nPress ESCAPE to end run.\n');
fprintf('\nStarting run %i at %s \n',cfg.RUN_ID,datestr(now,'HH:MM:SS am'));
fprintf('RUN ID: %i\n\n',cfg.RUN_ID);
% commandwindow;
% WaitSecs(0.1);

%% GUI setup
screenSize = get(0, 'ScreenSize');
fig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none',...
    'Position',[screenSize(3)/4 screenSize(4)/4 900 600],'NumberTitle','off');
ax = axes('Parent',fig,'Position',[0 0 1 1],'Visible','off');
hText = text(0.5, 0.5, '', ...
    'FontSize', cfg.stim_font_size, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Units','normalized', ...
    'Parent', ax);
stopFig = figure('Name','Stop','NumberTitle','off','MenuBar','none','ToolBar','none',...
    'Position',[300 100 200 80]);
setappdata(0, 'stopReq', false);
set(fig,     'WindowKeyPressFcn', @(~,evt) setappdata(0,'stopReq', getappdata(0,'stopReq') || strcmpi(evt.Key,'escape')));
set(stopFig, 'WindowKeyPressFcn', @(~,evt) setappdata(0,'stopReq', getappdata(0,'stopReq') || strcmpi(evt.Key,'escape')));
uicontrol(stopFig,'Style','pushbutton','String','Stop','FontSize',14,'Position',[50 20 100 40],...
    'Callback', @(~,~) setappdata(0,'stopReq',true));
set(fig,    'CloseRequestFcn', 'setappdata(0,''stopReq'',true); delete(gcbf);');
set(stopFig,'CloseRequestFcn', 'setappdata(0,''stopReq'',true); delete(gcbf);');

%% Instructions and sync beeps
instructions = [
    'INSTRUCTIONS\n\n' ...
    'When text appears on the screen,\n'...
    'Read as quickly and accurately as possible.\n\n' ...
    'Press any key to begin...'
];
set(hText, 'String', sprintf(instructions), ...
    'FontSize', 55, ...
    'Color', 'black'); % Show instructions
figure(fig); % Bring main window to front
set(fig, 'WindowKeyPressFcn', @(src,~) uiresume(src));
uiwait(fig); % Wait for user keypress to continue
set(fig, 'WindowKeyPressFcn', ''); % Remove keypress handler
set(hText, 'String', ''); 
drawnow; % Clear text

% Start time
baseGetSecs = GetSecs();
baseClock   = datetime('now','TimeZone','local');

flipSyncState = ~flipSyncState;
welcomeMessageTime = GetSecs();
log_event(eventFile, cfg.DIGOUT, welcomeMessageTime, [], [], [], [], 0, 'Instructions', flipSyncState);

if getappdata(0,'stopReq')
    flipSyncState = ~flipSyncState;
    code = TRIG_KEY;
    log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], [], [], code, 'Escape/Stop', flipSyncState);
    return
end

%% Trial Loop
% Initialize lag diagnostics
lagBuffer = zeros(1, 5000);
lagIndex = 1;
lagCount = 0;
runStartTime = GetSecs();

    for idxTrial = 1:nTrials
        % Check for exit keypress
        if getappdata(0,'stopReq')
            flipSyncState = ~flipSyncState;
            code = TRIG_ITI + TRIG_KEY;
            log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], [], [], code, 'Escape/Stop', flipSyncState);
            break
        end

        % Trial parameters and stimulus preparation
        isSpeak = ~DAF_Trials.catch(idxTrial);
        if DAF_Trials.catch(idxTrial)
            trialType = 'catch';
        else
            trialType = 'speech';
        end
        fixColor = [180 180 180];
        if ~isSpeak
            fixColor = [255 0 0];
        end
        text_stim = DAF_Trials.sentence{idxTrial};
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
            text_stim_wrapped_str = strjoin(lines, newline);
        else
            text_stim_wrapped_str = text_stim;
        end
        delay_ms = round(DAF_Trials.delay(idxTrial));
        delay_samples = delayLUT(int32(delay_ms));

        % Flush slave playback audio buffers before trial start
        PsychPortAudio('FillBuffer', pa_slave3, zeros(pa_channels, cfg.audio_frame_size * maxDelayFrames));
        reset(vfd);

        % ITI with Fixation cross
        Screen('FillRect', window, cfg.bg_color);
        DrawFormattedText(window, '*', 'center', 'center', fixcolor);
        flipSyncState = ~flipSyncState;
        [itiFixOnTime, ~] = Screen('Flip', window);
        DAF_Trials.start_time(idxTrial) = baseClock + seconds(itiFixOnTime - baseGetSecs);
        ItiDuration = ITI_S(1) + (ITI_S(2) - ITI_S(1)) .* rand(1);
        code = TRIG_ITI;
        log_event(eventFile, cfg.DIGOUT, itiFixOnTime, ItiDuration, [], trialType, [], code, 'ITI Fixation', flipSyncState);
        
        tEnd = itiFixOnTime + ItiDuration;
        while GetSecs < tEnd && ~getappdata(0,'stopReq')
            [isDown, ~, kc] = KbCheck(cfg.KEYBOARD_ID);
            if isDown && kc(keyCodeEscape)
                setappdata(0,'stopReq',true);
                flipSyncState = ~flipSyncState;
                code = TRIG_KEY;
                log_event(eventFile, cfg.DIGOUT, GetSecs(), [], [], trialType, [], code, 'Escape/Stop', flipSyncState);
                break
            end
            WaitSecs(0.01);
        end
        if getappdata(0,'stopReq'), break; end

        % Pre-sentence blank screen
        Screen('FillRect', window, cfg.bg_color);
        flipSyncState = ~flipSyncState;
        [trialOnsetFlip, ~] = Screen('Flip', window);
        log_event(eventFile, cfg.DIGOUT, trialOnsetFlip, [], [], trialType, [], TRIG_TRIAL, 'Trial Onset', flipSyncState);
        WaitSecs(cfg.delay_dur);

        % DAF on
        if isSpeak && delay_ms > 0
            dafTriggerTime = PsychPortAudio('Start', pa_slave3, 0, 0, 1);
            flipSyncState = ~flipSyncState;
            code = TRIG_DAF;
            log_event(eventFile, cfg.DIGOUT, dafTriggerTime, [], [], trialType, [], code, 'DAF On', flipSyncState);
        end

        % Visual ON
        Screen('FillRect', window, cfg.bg_color);
        DrawFormattedText(window, text_stim_wrapped_str, 'center', 'center', [0 0 0]);
        flipSyncState = ~flipSyncState;
        [stimOnsetTime, ~] = Screen('Flip', window);
        DAF_Trials.visual_onset_time(idxTrial) = baseClock + seconds(stimOnsetTime - baseGetSecs);
        code = TRIG_VISUAL;
        log_event(eventFile, cfg.DIGOUT, stimOnsetTime, [], [], trialType, text_stim, code, 'Visual Onset', flipSyncState);

        % Streaming Loop
        if isSpeak && delay_ms > 0
            [isDown, ~, kc] = KbCheck(cfg.KEYBOARD_ID);
            if isDown && kc(keyCodeEscape), setappdata(0,'stopReq',true); end
            frameCounter = 0;
            trialStart = dafTriggerTime;
            while (GetSecs - trialStart) < cfg.text_stim_dur && ~getappdata(0,'stopReq')
                tStart = GetSecs;
                audioIn = PsychPortAudio('GetAudioData', pa_rec, cfg.audio_frame_size / cfg.audio_sample_rate);
                if isempty(audioIn)
                    pause(0.001);
                    continue;
                end
                delayed = vfd(audioIn, delay_samples);
                audioOut = max(min(cfg.audio_playback_gain * delayed, 1), -1);
                if size(audioOut,2) > 1, audioOut = audioOut(:); end
                audioOut = [audioOut.'; audioOut.'];  % 2 x N
                PsychPortAudio('FillBuffer', pa_slave3, audioOut); % Output to slave device buffer
                
                % Record lag for diagnostics
                lag = max((GetSecs - tStart)*1000 - (cfg.audio_frame_size/cfg.audio_sample_rate*1000), 0);
                lagBuffer(lagIndex) = lag;
                lagIndex = mod(lagIndex, 5000) + 1;
                lagCount = min(lagCount + 1, 5000);

                frameCounter = frameCounter + 1;
                pause(0.001);
            end
        else
            WaitSecs(cfg.text_stim_dur); % Non-speak or no delay
        end

        % Stop DAF playback and log trigger
        if isSpeak && delay_ms > 0
            PsychPortAudio('Stop', pa_slave3, 1, 1);
            reset(vfd);
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
        writetable(DAF_Trials, cfg.TRIAL_FILENAME, 'Delimiter','\t', 'FileType','text'); %potentially move if lag?
    end

%% Cleanup
log_event(eventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero', 0); 

% end
flipSyncState = ~flipSyncState;
messageTime = GetSecs();
log_event(eventFile, cfg.DIGOUT, messageTime, [], [], [], [], 0, 'End Message', flipSyncState);

fprintf('\nTask %s, session %s, run %i for %s ended at %s\n',cfg.TASK,cfg.SESSION_LABEL,cfg.RUN_ID,cfg.SUBJECT,datetime("now",'HH:MM:SS'));
fprintf('\nRUN ID: %i\n',cfg.RUN_ID);

WaitSecs(2);

try PsychPortAudio('Stop', pa_rec, 1, 1); catch, end
try PsychPortAudio('Close', pa_rec); catch, end

try Screen('CloseAll'); catch, end
try if ishghandle(fig),     close(fig);     end; catch, end
try if ishghandle(stopFig), close(stopFig); end; catch, end
clear onCleanupTasks