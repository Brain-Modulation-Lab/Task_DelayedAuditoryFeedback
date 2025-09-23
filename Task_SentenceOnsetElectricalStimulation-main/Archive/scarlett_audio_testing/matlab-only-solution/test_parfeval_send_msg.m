% to shut down all workers:  delete(gcp('nocreate'))

% First, create a parallel pool if necessary
if isempty(gcp())
    parpool('local', 1);
end

% Get the worker to construct a data queue on which it can receive
% messages from the client
workerQueueConstant = parallel.pool.Constant(@parallel.pool.PollableDataQueue);

% Get the worker to send the queue object back to the client
workerQueueClient = fetchOutputs(parfeval(@(x) x.Value, 1, workerQueueConstant));

% Get the worker to start waiting for messages
future = parfeval(@doStuff, 1, workerQueueConstant);

% Send a few messages to the worker
for idx = 1:10
    send(workerQueueClient, idx);
end
% Send [] as a "poison pill" to the worker to get it to stop
send(workerQueueClient, []);

% Get the result
fetchOutputs(future)

% This function gets the worker to keep processing messages from the client
function out = doStuff(qConstant)
q = qConstant.Value;
out = 0;
while true
    % Wait for a message
    data = poll(q, Inf);
    if isempty(data)
        return
    else
        out = out + data;
    end
end

end