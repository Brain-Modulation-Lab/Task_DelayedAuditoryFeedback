

function [level, audio_all] = speech_onset_detection(recording_handle, detection_ops)

starttime = GetSecs; 

assert(isfield(detection_ops,'loudness_threshold'))

if ~isfield(detection_ops,'waitscan_seconds')
    detection_ops.waitscan_seconds = 0.005; % 5ms default
end
if ~isfield(detection_ops,'repetitions')
    detection_ops.repetitions = 0; % loop indefinitely until detection
end
if ~isfield(detection_ops,'when')
    detection_ops.when = 0; % start immediately on function call
end
if ~isfield(detection_ops,'max_dur_seconds')
    detection_ops.max_dur_seconds = 2; % default to timeout at 2 seconds
end

endtime = starttime + detection_ops.max_dur_seconds; % quit after reaching this time
audios={};
PsychPortAudio('Start', recording_handle, detection_ops.repetitions, detection_ops.when);
level=0;
%flushing buffer
PsychPortAudio('GetAudioData', recording_handle);

%% detection loop
audio_all = [];
while level < detection_ops.loudness_threshold && GetSecs < endtime
    audio_in_t = PsychPortAudio('GetAudioData', recording_handle);
    audio_all = [audio_all audio_in_t];

    if ~isempty(audio_in_t)
        level = max(abs((audio_in_t)));      
    else
        level = 0;
    end
    if level < detection_ops.loudness_threshold
        WaitSecs(detection_ops.waitscan_seconds); % Wait for waitscan_seconds before next scan    
    end
end
% 
% plot(audio_all, 'k');
% drawnow;
% PsychPortAudio('Stop', recording_handle);

        