
% First, create a parallel pool if necessary
if isempty(gcp())
    parpool('local', 1);
end

% Get the worker to construct a data queue on which it can receive messages from the client
workerQueueConstant = parallel.pool.Constant(@parallel.pool.PollableDataQueue);

% Get the worker to send the queue object back to the client
workerQueueClient = fetchOutputs(parfeval(@(x) x.Value, 1, workerQueueConstant));

% Get the worker to start waiting for messages
filename = "C:\Users\abush\Desktop\audio_testing3.wav";
future = parfeval(@record_audio, 1, filename, workerQueueConstant);
future.Diary

% Send a message to start recording
% send(workerQueueClient, 'start');

% Runt he task

% Send a message to stop recording
send(workerQueueClient, 'stop');

% Get the result (recorded audio data)
audioData = fetchOutputs(future);

