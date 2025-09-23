% to run this script from the command line, use the following

% "C:\Program Files\MATLAB\R2022b\bin\matlab.exe" -nodisplay -nosplash -nodesktop -r "run('D:\Task\Task_SentenceOnsetElectricalStimulation\pilot_scarlett4i4_multichan_acquisition.m'); exit;"

%%
device = 'Focusrite USB ASIO';
driver = 'ASIO'; 
Fs = 44100; % sampling frequency
% set up device reader (for recording)
deviceReader = audioDeviceReader('SampleRate',Fs, ...
'Device',device, ...
'BitDepth','24-bit integer', ...
'Driver',driver, ...
'NumChannels', 3);

setup(deviceReader); 


fileWriter = dsp.AudioFileWriter("C:\Users\abush\Desktop\audio_testing.wav", 'FileFormat','WAV');
disp('Speak into microphone now.')

tic
while toc < 5
    acquiredAudio = deviceReader();
    fileWriter(acquiredAudio);
end
disp('Recording complete.')

release(deviceReader)
release(fileWriter)

%% 


% Define the URL of the Python script
start_url = 'http://localhost:8080/start';
stop_url = 'http://localhost:8080/stop';

start_url_args = 'http://localhost:8080/start?save_to=~\audio_testing.wav';

cmd /c curl -X POST --data "save_to=audio_testing.wav" http://localhost:8080/start?save_to=audio_testing.wav

cmd /c curl -X POST --data "" http://localhost:8080/start?save_to=C:\Users\abush\Desktop\audio_testing2.wav

r"C:\Users\abush\Desktop\audio_testing2.wav"

% Define the filename to save the recording
filename = 'C:\Users\abush\Desktop\audio_testing.wav';


params(1).save_to = filename;

% Send HTTP POST request to start recording
options = weboptions('RequestMethod', 'post', 'MediaType', 'auto');
response = webwrite(start_url, 'save_to', filename);

% Check if recording started successfully
if strcmp(response.status, 'Recording started')
    disp('Recording started successfully.');
else
    disp('Failed to start recording.');
    return; % Exit script if recording failed to start
end

% Here, you would run your MATLAB task

% After running the task, send HTTP POST request to stop recording
response = webwrite(stop_url, options);

% Check if recording stopped successfully
if strcmp(response.status, 'Recording stopped')
    disp('Recording stopped successfully.');
else
    disp('Failed to stop recording.');
    % Handle failure appropriately
end


import matlab.net.http.*
import matlab.net.http.field.*
header = [ContentTypeField( 'application/json' ), ...
    HeaderField('save_to',filename)];

request = RequestMessage('PUT', ...
    header, '');
options = matlab.net.http.HTTPOptions();
response = request.send(start_url, options);








