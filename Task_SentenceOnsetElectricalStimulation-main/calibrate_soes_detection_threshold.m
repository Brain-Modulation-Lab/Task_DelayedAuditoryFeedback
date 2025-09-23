
function [] = calibrate_soes_detection_threshold(cfg)


stop_flag = 0; 
max_iter = 10;
i=0;
% Repeat short audio recordings until an attempt is accepted by the user
while stop_flag~=1 && i <= max_iter
    
    disp('Recording audio for speech detection calibration...'); 
    
    duration = 10; 
    % Start audio recording
    % PsychPortAudio('Start', cfg.PA_RECORDER_HANDLE, duration);
    PsychPortAudio('Start', cfg.PA_RECORDER_HANDLE, [], 0);
    % PsychPortAudio('GetStatus', cfg.PA_RECORDER_HANDLE)
    
    record_start_time = GetSecs();
    audioData = []; 
    while GetSecs() < record_start_time + duration 
        d = PsychPortAudio('GetAudioData', cfg.PA_RECORDER_HANDLE);
        audioData = [audioData d]; 
        WaitSecs(0.1);
    end
    
    % % Wait for the specified recording duration
    % pause(duration);
    
    % Stop recording and retrieve audio data
    PsychPortAudio('Stop', cfg.PA_RECORDER_HANDLE);
    % audioData = PsychPortAudio('GetAudioData', cfg.PA_RECORDER_HANDLE);
    % PsychPortAudio('Close', cfg.PA_RECORDER_HANDLE);
    
    % Plot the recorded audio data
    t = linspace(0, duration, length(audioData));
    tiledlayout('flow'); nexttile
    plot(t, audioData, 'k');
    title('Recorded Audio Waveform');
    xlabel('Time (s)');
    ylabel('Amplitude');
    
    % Let the user select a time window
    disp('Select a time window for analysis by clicking and dragging on the plot.');
    % [x, ~] = ginput(2);
    hRect = drawrectangle(); 
    x = hRect.Position(1) + [0 hRect.Position(3)]; 
    % x = sort(x);  % Ensure x(1) is the start and x(2) is the end
    
    % Extract the selected time window
    startIndex = find(t >= x(1), 1);
    endIndex = find(t <= x(2), 1, 'last');
    selectedData = audioData(startIndex:endIndex);
    
    selectedData = abs(selectedData); % take amplitude
    
    % Compute statistics on the selected time window
    medianVal = median(selectedData);
    lowerQuartile = prctile(selectedData, 25);
    upperQuartile = prctile(selectedData, 75);
    prctile90 = prctile(selectedData, 90);
    
    nexttile
    histogram(selectedData); 
    set(gca,'yscale','log');
    xline(prctile90, 'r', 'linewidth', 2,  'DisplayName', '90th percentile'); 
    xline(prctile90*cfg.SPEECH_LEVEL_MAD_MULTIPLIER, 'r', 'linewidth', 2,  'DisplayName', 'suggested threshold'); 
    legend; 
    xlabel('|Amplitude|'); 
    
    % Display the statistics
    fprintf('Median: %.2f\n', medianVal);
    fprintf('Lower Quartile: %f\n', lowerQuartile);
    fprintf('Upper Quartile: %f\n', upperQuartile);
    
    % Prompt the user to save the threshold or try again
    cmd='1';    
    fprintf('Do you want to save this threshold?\n');
    prompt = sprintf(' Save Threshold: 1=Yes | 2=No, try again');
    answer = input(prompt,'s');
    
    if isempty(answer)
        answer = cmd;
    else
        answer = strtrim(answer);
    end
    if ~ismember(answer,{'1','2'})
        clear onCleanupTasks
        error('Task canceled by user')
    else
        cmd = answer;
    end
    
    if strcmp(cmd,'1') % Audio Calibration    
        save(cfg.AUDIO_CALIBRATION_FILENAME, 'medianVal', 'lowerQuartile', 'upperQuartile', 'selectedData', 'audioData');
        fprintf('Threshold saved to %s.\n', cfg.AUDIO_CALIBRATION_FILENAME);
        stop_flag = 1; 
    else
        disp('Try recording again.');
    end

    i = i + 1;
end


