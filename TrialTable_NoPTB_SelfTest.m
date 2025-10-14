function [DAF_Trials, info] = TrialTable_NoPTB_SelfTest(cfg)
% TrialTable_NoPTB_SelfTest  Build & validate DAF trial table without PTB.
%
% Usage:
%   DAF_Trials = TrialTable_NoPTB_SelfTest();              % uses defaults below
%   DAF_Trials = TrialTable_NoPTB_SelfTest(cfg);           % pass your cfg
%   [DAF_Trials, info] = TrialTable_NoPTB_SelfTest(cfg);   % also returns timing & checks
%
% This script:
%   - loads sentences from cfg.PATH_TASK/stimuli/cfg.daf_sentences
%   - builds per-block trial order with max repeats constraints
%   - supports repeating identical order across blocks
%   - validates constraints and timing
%   - writes trials.tsv in pwd
%
% No Psychtoolbox required.

%% --- Defaults (edit if cfg not provided) ---------------------------------
if nargin < 1 || isempty(cfg)
    cfg = struct();
end
if ~isfield(cfg,'PATH_TASK'),  cfg.PATH_TASK = '/Users/samhansen/Documents/MATLAB/Guenther/Task_DelayedAuditoryFeedback/'; end
if ~isfield(cfg,'daf_sentences'), cfg.daf_sentences = 'daf_sentences.tsv'; end
if ~isfield(cfg,'n_blocks'),   cfg.n_blocks = 3; end
if ~isfield(cfg,'delayOptions'), cfg.delayOptions = [150 250]; end  % ms
if ~isfield(cfg,'max_stim_repeats'),  cfg.max_stim_repeats = 2; end
if ~isfield(cfg,'max_delay_repeats'), cfg.max_delay_repeats = 4; end
if ~isfield(cfg,'same_trials_across_blocks'), cfg.same_trials_across_blocks = false; end
if ~isfield(cfg,'catchRatio'), cfg.catchRatio = 0.10; end
if ~isfield(cfg,'stim_max_char_per_line'), cfg.stim_max_char_per_line = 38; end
if ~isfield(cfg,'max_trials'), cfg.max_trials = []; end
if ~isfield(cfg,'RNG_SEED'), cfg.RNG_SEED = []; end

if ~isempty(cfg.RNG_SEED), rng(cfg.RNG_SEED); end

%% --- Load sentences -------------------------------------------------------
sentPath = fullfile(cfg.PATH_TASK,'stimuli',cfg.daf_sentences);
if ~isfile(sentPath)
    error('Sentences file not found: %s', sentPath);
end
lines = readlines(sentPath);
lines = strip(lines);
lines(lines=="") = [];
sentences = cellstr(lines);
nSentences = numel(sentences);
cfg.delayOptions = cfg.delayOptions(:);
nDelays    = numel(cfg.delayOptions);

% Quick feasibility guards
if nSentences < 1 || nDelays < 1
    error('Need at least 1 sentence and 1 delay.');
end
if nSentences == 1 && cfg.max_stim_repeats < 1
    error('With a single stimulus, max_stim_repeats must be >= 1.');
end
if nDelays == 1 && cfg.max_delay_repeats < 1
    error('With a single delay, max_delay_repeats must be >= 1.');
end

%% --- STEP 4: Build per-block order with constraints (NO HELPERS) ---------
pairSentences = repmat((1:nSentences)', nDelays, 1);
pairDelays    = reshape(repmat(cfg.delayOptions, nSentences, 1), [], 1);
pairsN        = numel(pairSentences);

MAX_ATTEMPTS = 50;

t0 = tic;
% Build one constrained block
attempt = 0; ok = false;
while ~ok && attempt < MAX_ATTEMPTS
    attempt = attempt + 1;

    idxPool = randperm(pairsN);     % randomize pool each attempt
    fs = zeros(pairsN,1);           % final sentences for this block
    fd = zeros(pairsN,1);           % final delays for this block

    curStim = NaN; stimRun = 0;
    curDelay = NaN; delayRun = 0;
    ok = true;

    for k = 1:pairsN
        % randomly permute remaining candidates each step
        remaining = idxPool(k:end);
        remaining = remaining(randperm(numel(remaining)));

        picked = NaN;
        for cand = remaining
            s = pairSentences(cand);
            d = pairDelays(cand);

            nextStimRun  = (isnan(curStim)  || s ~= curStim)  * 1 + (s == curStim)  * (stimRun  + 1);
            nextDelayRun = (isnan(curDelay) || d ~= curDelay) * 1 + (d == curDelay) * (delayRun + 1);

            if nextStimRun <= cfg.max_stim_repeats && nextDelayRun <= cfg.max_delay_repeats
                picked = cand; break;
            end
        end

        % soft fallback to avoid deadlock: pick first remaining if none fit
        if isnan(picked), picked = remaining(1); end

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
        cfg.max_stim_repeats, cfg.max_delay_repeats, MAX_ATTEMPTS);
end

% Build across blocks
if cfg.same_trials_across_blocks
    finalSentences = repmat(fs, cfg.n_blocks, 1);
    finalDelays    = repmat(fd, cfg.n_blocks, 1);
else
    finalSentences = zeros(pairsN * cfg.n_blocks, 1);
    finalDelays    = zeros(pairsN * cfg.n_blocks, 1);
    writeIdx = 1;
    for b = 1:cfg.n_blocks
        attempt = 0; ok = false;
        while ~ok && attempt < MAX_ATTEMPTS
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

                    nextStimRun  = (isnan(curStim)  || s ~= curStim)  * 1 + (s == curStim)  * (stimRun  + 1);
                    nextDelayRun = (isnan(curDelay) || d ~= curDelay) * 1 + (d == curDelay) * (delayRun + 1);

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
            error('Block %d: could not satisfy max repeats after %d attempts.', b, MAX_ATTEMPTS);
        end
        finalSentences(writeIdx:writeIdx+pairsN-1) = bs;
        finalDelays(writeIdx:writeIdx+pairsN-1)    = bd;
        writeIdx = writeIdx + pairsN;
    end
end
buildTime_sec = toc(t0);

%% --- Cap total trials (optional) ------------------------------------------
blockNtrials = pairsN;
nTrialsPlanned = cfg.n_blocks * blockNtrials;
if ~isempty(cfg.max_trials), nTrials = min(nTrialsPlanned, cfg.max_trials); else, nTrials = nTrialsPlanned; end

trialSentIdx = zeros(nTrials,1);
trialDelays  = zeros(nTrials,1);
trialBlock   = zeros(nTrials,1);

writeIdx = 1;
for b = 1:cfg.n_blocks
    rem = nTrials - (writeIdx-1);
    if rem <= 0, break; end
    thisN = min(blockNtrials, rem);
    src1 = (b-1)*blockNtrials + 1;
    src2 = src1 + thisN - 1;
    trialSentIdx(writeIdx:writeIdx+thisN-1) = finalSentences(src1:src2);
    trialDelays(writeIdx:writeIdx+thisN-1)  = finalDelays(src1:src2);
    trialBlock(writeIdx:writeIdx+thisN-1)   = b;
    writeIdx = writeIdx + thisN;
end

%% --- Catch trials ----------------------------------------------------------
nCatch = round(nTrials * cfg.catchRatio);
catchVec = false(nTrials,1);
if nCatch > 0
    catchVec(randperm(nTrials, nCatch)) = true;
end

%% --- Optional wrapping (same as your task) ---------------------------------
text_wrapped_all = cell(nSentences,1);
nl = sprintf('\n');
for si = 1:nSentences
    text_stim = regexprep(sentences{si}, '\r', '');
    if cfg.stim_max_char_per_line > 0
        w = split(string(text_stim));
        cur = ""; lines2 = strings(0,1);
        for ii = 1:numel(w)
            nxt = strtrim(cur + " " + w(ii));
            if strlength(nxt) <= cfg.stim_max_char_per_line
                cur = nxt;
            else
                if strlength(cur)>0, lines2(end+1) = cur; end %#ok<AGROW>
                cur = w(ii);
            end
        end
        if strlength(cur)>0, lines2(end+1) = cur; end %#ok<AGROW>
        text_wrapped_all{si} = char(strjoin(lines2, nl));
    else
        text_wrapped_all{si} = char(text_stim);
    end
end

%% --- Build table -----------------------------------------------------------
DAF_Trials = table( ...
    (1:nTrials).', ...
    trialBlock(:), ...
    sentences(trialSentIdx), ...
    trialSentIdx(:), ...
    trialDelays(:), ...
    catchVec(:), ...
    'VariableNames', {'trialnum','block_id','sentence','sentence_idx','delay','catch'} ...
);

%% --- Validation ------------------------------------------------------------
% 1) Max consecutive repeats per block
violStim = false; violDelay = false;
for b = 1:cfg.n_blocks
    m = DAF_Trials.block_id == b;
    sIdx = DAF_Trials.sentence_idx(m);
    dVal = DAF_Trials.delay(m);

    if any_consec_over_cap(sIdx, cfg.max_stim_repeats),  violStim  = true; end
    if any_consec_over_cap(dVal, cfg.max_delay_repeats), violDelay = true; end
end

% 2) Same order across blocks (if requested and not truncated mid-block)
sameAcross = NaN;
if cfg.same_trials_across_blocks && nTrials >= blockNtrials*2
    baseS = finalSentences(1:blockNtrials);
    baseD = finalDelays(1:blockNtrials);
    sameAcross = true;
    for b = 2:cfg.n_blocks
        s = finalSentences((b-1)*blockNtrials + (1:blockNtrials));
        d = finalDelays((b-1)*blockNtrials + (1:blockNtrials));
        if ~isequal(s, baseS) || ~isequal(d, baseD), sameAcross = false; break; end
    end
end

% 3) Timing expectation check (only for the Slack test case)
expectFast = (cfg.n_blocks==3 && nSentences==10 && nDelays==2 && ...
              cfg.max_stim_repeats==2 && cfg.max_delay_repeats==4);
timingOK = (~expectFast) || (buildTime_sec < 1.0);

%% --- Write TSV -------------------------------------------------------------
outFile = fullfile(pwd, sprintf('trials_%s.tsv', datestr(now,'yyyymmdd_HHMMSS')));
writetable(DAF_Trials, outFile, 'FileType','text','Delimiter','\t');

%% --- Return info & summary -------------------------------------------------
info = struct('buildTime_sec',buildTime_sec, ...
              'violStim',violStim,'violDelay',violDelay, ...
              'sameAcrossBlocks',sameAcross, ...
              'outFile',outFile, ...
              'pairsPerBlock',pairsN, ...
              'nTrials',nTrials);

fprintf('Build time: %.3f s | pairs/block: %d | trials total: %d\n', buildTime_sec, pairsN, nTrials);
if expectFast
    fprintf('Timing check (<1s): %s\n', ternary(timingOK,'OK','FAIL'));
end
fprintf('Stim repeat violations: %d | Delay repeat violations: %d\n', violStim, violDelay);
if ~isnan(sameAcross)
    fprintf('Same trials across blocks: %s\n', ternary(sameAcross,'YES','NO'));
end
fprintf('Wrote: %s\n', outFile);

% Hard errors if constraints violated
if violStim
    error('Validation failed: stimulus run-length exceeded max_stim_repeats=%d.', cfg.max_stim_repeats);
end
if violDelay
    error('Validation failed: delay run-length exceeded max_delay_repeats=%d.', cfg.max_delay_repeats);
end
if expectFast && ~timingOK
    error('Performance failed: build took %.3f s (expected < 1.0 s).', buildTime_sec);
end

end

%% --- Local inline helpers (no external deps) ------------------------------
function tf = any_consec_over_cap(v, cap)
if isempty(v), tf = false; return; end
run = 1; tf = false;
for i = 2:numel(v)
    if isequal(v(i), v(i-1))
        run = run + 1;
        if run > cap, tf = true; return; end
    else
        run = 1;
    end
end
end

function s = ternary(cond, a, b)
if cond, s = a; else, s = b; end
end
