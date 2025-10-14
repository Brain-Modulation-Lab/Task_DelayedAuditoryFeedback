function [cfg, DAF_Trials, text_wrapped_all] = create_trials_table(cfg)
% create_trials_table  Build DAF trial table with max-repeat constraints.
% Usage (inside Task_DelayedAuditoryFeedback.m):
%   [cfg, DAF_Trials] = create_trials_table(cfg);
%   % cfg.TRIAL_TABLE is also populated.

%% Load sentences
sentPath = fullfile(cfg.PATH_TASK,'stimuli',cfg.daf_sentences);
lines = readlines(sentPath);
lines = strip(lines);
lines(lines == "") = [];
sentences = cellstr(lines);

% Counts and delay vector
nSentences = numel(sentences);
cfg.delayOptions = cfg.delayOptions(:);
nDelays = numel(cfg.delayOptions);

%% Build all (sentence, delay) pairs
pairSentences = repmat((1:nSentences)', nDelays, 1);
pairDelays    = reshape(repmat(cfg.delayOptions, nSentences, 1), [], 1);
pairsN        = numel(pairSentences);     % trials per block
blockNtrials  = pairsN;

max_attempts = 50;

%% Constrained permutation for one block (inline, no helpers)
attempt = 0; ok = false;
while ~ok && attempt < max_attempts
    attempt = attempt + 1;

    idxPool = randperm(pairsN);
    fs = zeros(pairsN,1);     % final sentences for this block
    fd = zeros(pairsN,1);     % final delays for this block

    curStim = NaN; stimRun = 0;
    curDelay = NaN; delayRun = 0;
    ok = true;

    for k = 1:pairsN
        remaining = idxPool(k:end);
        remaining = remaining(randperm(numel(remaining)));

        picked = NaN;
        for cand = remaining
            s = pairSentences(cand);
            d = pairDelays(cand);

            if isnan(curStim) || s ~= curStim, nextStimRun = 1; else, nextStimRun = stimRun + 1; end
            if isnan(curDelay) || d ~= curDelay, nextDelayRun = 1; else, nextDelayRun = delayRun + 1; end

            if nextStimRun <= cfg.max_stim_repeats && nextDelayRun <= cfg.max_delay_repeats
                picked = cand; break;
            end
        end

        if isnan(picked)            % soft fallback to avoid deadlock
            picked = remaining(1);
        end

        fs(k) = pairSentences(picked);
        fd(k) = pairDelays(picked);

        if fs(k) == curStim, stimRun = stimRun + 1; else, curStim = fs(k); stimRun = 1; end
        if fd(k) == curDelay, delayRun = delayRun + 1; else, curDelay = fd(k); delayRun = 1; end

        if stimRun > cfg.max_stim_repeats || delayRun > cfg.max_delay_repeats
            ok = false; break;
        end
    end
end

if ~ok
    error('Could not satisfy max repeats (stim=%d, delay=%d) after %d attempts.', ...
        cfg.max_stim_repeats, cfg.max_delay_repeats, max_attempts);
end

%% Build across blocks (reuse or per-block)
if isfield(cfg,'same_trials_across_blocks') && cfg.same_trials_across_blocks
    finalSentences = repmat(fs, cfg.n_blocks, 1);
    finalDelays    = repmat(fd, cfg.n_blocks, 1);
else
    finalSentences = zeros(pairsN * cfg.n_blocks, 1);
    finalDelays    = zeros(pairsN * cfg.n_blocks, 1);
    writeIdx = 1;
    for b = 1:cfg.n_blocks
        attempt = 0; ok = false;
        while ~ok && attempt < max_attempts
            attempt = attempt + 1;

            idxPool = randperm(pairsN);
            bs = zeros(pairsN,1);
            bd = zeros(pairsN,1);

            curStim = NaN; stimRun = 0;
            curDelay = NaN; delayRun = 0;
            ok = true;

            for k = 1:pairsN
                remaining = idxPool(k:end);
                remaining = remaining(randperm(numel(remaining)));

                picked = NaN;
                for cand = remaining
                    s = pairSentences(cand);
                    d = pairDelays(cand);

                    if isnan(curStim) || s ~= curStim, nextStimRun = 1; else, nextStimRun = stimRun + 1; end
                    if isnan(curDelay) || d ~= curDelay, nextDelayRun = 1; else, nextDelayRun = delayRun + 1; end

                    if nextStimRun <= cfg.max_stim_repeats && nextDelayRun <= cfg.max_delay_repeats
                        picked = cand; break;
                    end
                end
                if isnan(picked), picked = remaining(1); end

                bs(k) = pairSentences(picked);
                bd(k) = pairDelays(picked);

                if bs(k) == curStim, stimRun = stimRun + 1; else, curStim = bs(k); stimRun = 1; end
                if bd(k) == curDelay, delayRun = delayRun + 1; else, curDelay = bd(k); delayRun = 1; end

                if stimRun > cfg.max_stim_repeats || delayRun > cfg.max_delay_repeats
                    ok = false; break;
                end
            end
        end
        if ~ok
            error('Block %d: could not satisfy max repeats after %d attempts.', b, max_attempts);
        end
        finalSentences(writeIdx:writeIdx+pairsN-1) = bs;
        finalDelays(writeIdx:writeIdx+pairsN-1)    = bd;
        writeIdx = writeIdx + pairsN;
    end
end

%% Assemble trials across blocks with optional cap
nTrialsPlanned = cfg.n_blocks * blockNtrials;
if isfield(cfg,'max_trials') && ~isempty(cfg.max_trials)
    nTrials = min(nTrialsPlanned, cfg.max_trials);
else
    nTrials = nTrialsPlanned;
end

trialSentIdx = zeros(nTrials,1);
trialDelays  = zeros(nTrials,1);
trialBlock   = zeros(nTrials,1);

writePtr = 1;
for b = 1:cfg.n_blocks
    rem = nTrials - (writePtr-1);
    if rem <= 0, break; end
    thisN   = min(blockNtrials, rem);
    src1    = (b-1)*blockNtrials + 1;
    src2    = src1 + thisN - 1;

    trialSentIdx(writePtr:writePtr+thisN-1) = finalSentences(src1:src2);
    trialDelays(writePtr:writePtr+thisN-1)  = finalDelays(src1:src2);
    trialBlock(writePtr:writePtr+thisN-1)   = b;

    writePtr = writePtr + thisN;
end

%% Catch trials
nCatch = round(nTrials * cfg.catchRatio);
catchVec = false(nTrials,1);
if nCatch > 0
    catchVec(randperm(nTrials, nCatch)) = true;
end

%% Pre-wrap sentences (for display)
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
                if strlength(cur)>0, lines(end+1) = cur; end %#ok<AGROW>
                cur = w(ii);
            end
        end
        if strlength(cur)>0, lines(end+1) = cur; end %#ok<AGROW>
        text_wrapped_all{si} = char(strjoin(lines, nl));
    else
        text_wrapped_all{si} = char(text_stim);
    end
end

%% Build table
DAF_Trials = table( ...
    (1:nTrials).', ...
    trialBlock(:), ...
    sentences(trialSentIdx), ...
    trialSentIdx(:), ...
    trialDelays(:), ...
    catchVec(:), ...
    'VariableNames', {'trialnum','block_id','sentence','sentence_idx','delay','catch'} ...
);

% Initialize columns that will be filled during runtime
DAF_Trials.start_time         = NaT(nTrials,1,'TimeZone','local');
DAF_Trials.visual_onset_time  = NaT(nTrials,1,'TimeZone','local');
DAF_Trials.visual_off_time    = NaT(nTrials,1,'TimeZone','local');
DAF_Trials.lag_mean           = nan(nTrials,1);

% Return in cfg (and as output)
cfg.TRIAL_TABLE = DAF_Trials;
end
