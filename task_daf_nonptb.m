function task_daf_nonptb(cfg)
% Audio flush at trial start: uses a brief ~30 ms prefill (zeros) instead of the long multi-frame flush loop.
% 0-ms delay trials: bypasses the audio path entirely (no reader/VFD/writer) instead of routing through the delay line.
% Hot loop load: removes per-frame lag math, drawnow throttling, and pause(0.001), keeping the streaming loop lean.
% Tail handling: ends each speech trial with a short ~20 ms silent tail (zeros) instead of flushing many frames + long waits.
% Delay filter: still uses dsp.VariableFractionalDelay (same algorithm as before).
% Devices & sample rate: unchanged (same audioDeviceReader/Writer, same device selection and cfg.audio_sample_rate).
% Beeps & visuals: unchanged (MATLAB sound() for beeps; MATLAB figure/text UI).
% Logging: event file is opened the same; trial-loop logging remains minimal (no added per-frame diagnostics).

%% Trial table
[cfg, trials] = create_trials_table(cfg);

%% Logging
eventFile = fopen(cfg.EVENT_FILENAME, 'w');
fprintf(eventFile,'onset\tduration\tsample\ttrial_type\tstim_file\tvalue\tevent_code\n');

%% Hardware setup (unchanged)
fprintf('Initializing psychtoolbox at %s for subject %s, %s task, session %s, run %i\n\n', ...
    datestr(now,'HH:mm:ss'), cfg.SUBJECT, cfg.TASK, cfg.SESSION_LABEL, cfg.RUN_ID);

fprintf('Initializing Keyboard...');
if isempty(cfg.KEYBOARD_ID)
    fprintf('\nNo keyboard selected, using default. Choose KEYBOARD_ID from this table:\n');
    if ~cfg.LOCAL_TEST
        devices = struct2table(PsychHID('Devices'));
    else
        devices = table();
        fprintf('Skipping PsychHID device enumeration for local test mode.\n');
    end
    disp(devices);
end

% Audio device setup and MATLAB Audio System Toolbox I/O (unchanged)
input_devices = getAudioDevices(audioDeviceReader);
for k = 1:length(input_devices)
    fprintf('%d: %s\n', k, input_devices{k});
end
inIdx = input('INPUT device #: ');

if ispc
    [~,host] = system('hostname'); host = deblank(host);
elseif ismac
    [~,host] = system('scutil --get LocalHostName'); host = deblank(host);
end
if strcmp(host,'BML-ALIENWARE2')
    reader = audioDeviceReader('SampleRate', cfg.audio_sample_rate, ...
        'SamplesPerFrame', cfg.audio_frame_size, ...
        'Device', 'Focusrite USB ASIO', 'Driver','ASIO');
else
    reader = audioDeviceReader('SampleRate', cfg.audio_sample_rate, ...
        'SamplesPerFrame', cfg.audio_frame_size, ...
        'Device', input_devices{inIdx});
end

output_devices = getAudioDevices(audioDeviceWriter);
for k = 1:length(output_devices)
    fprintf('%d: %s\n', k, output_devices{k});
end
outIdx = input('OUTPUT device #: ');

writer = audioDeviceWriter('SampleRate', cfg.audio_sample_rate, 'Device', output_devices{outIdx});
vfd   = dsp.VariableFractionalDelay('MaximumDelay', round(cfg.audio_sample_rate));

% Prime audio pipeline (unchanged)
for k = 1:10, writer(reader()); end

maxDelay_ms      = max(cfg.delay_values_ms);
maxDelayFrames   = ceil((maxDelay_ms/1000) * cfg.audio_sample_rate / cfg.audio_frame_size) + 5; %#ok<NASGU> % retained but unused after change
prefillSamples   = round(0.03 * cfg.audio_sample_rate); % ~30 ms prefill

%% Visual setup (unchanged)
screenSize = get(0, 'ScreenSize');
fig = figure('Name','DAF','Color','white','MenuBar','none','ToolBar','none', ...
             'Position',[screenSize(3)/4 screenSize(4)/4 900 600],'NumberTitle','off');
ax = axes('Parent',fig,'Position',[0 0 1 1],'Visible','off');
hText = text(0.5, 0.5, '', 'FontSize', cfg.stim_font_size, 'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','middle','Units','normalized','Parent', ax);
stopFig = figure('Name','Stop','NumberTitle','off','MenuBar','none','ToolBar','none','Position',[300 100 200 80]);
setappdata(0, 'stopReq', false);
uicontrol(stopFig,'Style','pushbutton','String','Stop','FontSize',14,'Position',[50 20 100 40], ...
    'Callback', @(~,~) setappdata(0,'stopReq',true));

%% Instructions and sync beeps (unchanged)
instructions = ['INSTRUCTIONS\n\n' 'When text appears on the screen,\n' 'Read as quickly and accurately as possible.\n\n' 'Press any key to begin...'];
set(hText, 'String', sprintf(instructions), 'FontSize', 55, 'Color', 'black');
figure(fig);
instrOn = GetSecs(); %#ok<NASGU>
set(fig, 'WindowKeyPressFcn', @(~,~) uiresume(fig));
uiwait(fig);
set(fig, 'WindowKeyPressFcn', '');
set(hText, 'String', ''); drawnow;
beepWave = 0.1 * sin(2*pi*1000*(0:1/cfg.audio_sample_rate:0.2));
set(hText, 'String', 'SYNC', 'FontSize', 48, 'Color', 'red'); drawnow;
for i = 1:3
    if i == 1, refTime = GetSecs; end %#ok<NASGU>
    sound(beepWave, cfg.audio_sample_rate);
    pause(0.5);
end
set(hText, 'String', ''); drawnow;

%% Trial loop (sound-path tweaks only)
baseGetSecs = GetSecs(); %#ok<NASGU>
baseClock   = datetime('now','TimeZone','local'); %#ok<NASGU>
flipSyncState = 0; %#ok<NASGU>
runStartTime  = GetSecs(); %#ok<NASGU>
goto_cleanup  = false;

for itrial = 1:cfg.ntrials
    [isDown, ~, kc] = KbQueueCheck;
    if isDown && kc(KbName('ESCAPE'))
        goto_cleanup = true; break; %#ok<NASGU>
    end

    delay_samples = round(cfg.audio_sample_rate * trials.delay(itrial) / 1000);

    % --- Minimal prefill instead of long multi-frame flush ---
    writer(zeros(prefillSamples,1));
    reset(vfd);

    set(hText, 'String', trials.stim{itrial}, 'FontSize', cfg.stim_font_size, 'Color', 'black'); drawnow;
    trialStart = GetSecs();

    if delay_samples <= 0
        % Bypass audio pipeline entirely for 0 ms delay (older script behavior)
        while (GetSecs - trialStart) < cfg.text_stim_dur && ~getappdata(0,'stopReq')
            % passive wait; no reader/vfd/writer calls
        end
    else
        % Standard DAF path (unchanged logic; steady per-frame processing)
        while (GetSecs - trialStart) < cfg.text_stim_dur && ~getappdata(0,'stopReq')
            audioIn  = reader();
            delayed  = vfd(audioIn, delay_samples);
            audioOut = max(min(cfg.audio_playback_gain * delayed, 1), -1);
            writer(audioOut);
        end
        % brief tail to finish any residual
        writer(zeros(round(0.02*cfg.audio_sample_rate),1));
        reset(vfd);
    end
end

%% Cleanup (unchanged)
release(reader); release(writer); release(vfd);
close(fig); close(stopFig);
fclose(eventFile);

end