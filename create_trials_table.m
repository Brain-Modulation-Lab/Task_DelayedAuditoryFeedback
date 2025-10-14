function trials = create_trials_table(cfg)

  %% Build table specifying condition for each trials (if not present)

  disp('constructing trials table');
  % conditions = sentences x stim_epoch x stim_freq x stim_loc

%% Load sentences and block randomization (with preallocation)
stimtable = readtable([cfg.PATH_TASK filesep 'stimuli' filesep cfg.STIM_SENTENCES_FILE],'Delimiter',',','FileType','text');  
stimlist = stimtable.stim; % Extract sentences as cell array
n_unique_stim = numel(stimlist); % Number of sentences

% For one block: all (sentence x delay) pairs
[sentenceIdxGrid, delayIdxGrid] = ndgrid(1:n_unique_stim, 1:numel(cfg.delay_values));
blockSentIdx = sentenceIdxGrid(:); % [nSentences*numel(delayOptions) x 1]
blockDelays = cfg.delay_values(delayIdxGrid(:)); % [nSentences*numel(delayOptions) x 1]
blockNtrials = numel(blockSentIdx); % Number of trials per block
nTrials = cfg.n_blocks * blockNtrials; % Total number of trials



%% TO DO - add a parameter which sets a maximum to the number of repeated sentences and to the number repeated delays
..... these 2 parameters should be set in the START_DAF cfg structure
    ..... test out that this doesn't hang for more than a second when max-rep-stim = 2 and max-rep-delay = 4 
..... [with 10 stim ID, 2 delays, 3 blocks]
..... also - include option to use the same stim order across blocks rather than do a different randomization across blocks

% Make trials table
trials = table([1:nTrials]','VariableNames',{'trialnum'});
trials.stim_id = zeros(nTrials, 1); % stim indices for all trials
trials.delay = zeros(nTrials, 1); % Delay values for all trials
trials.block = zeros(nTrials, 1); % Block number for all trials
trialCounter = 1; % Index for filling arrays
for b = 1:cfg.n_blocks
    blockOrder = randperm(blockNtrials); % Unique shuffle for this block
    trialRange = trialCounter:(trialCounter + blockNtrials - 1);
    trials.stim_id(trialRange) = blockSentIdx(blockOrder);
    trials.delay(trialRange)  = blockDelays(blockOrder);
    trials.block(trialRange)   = b;
    trialCounter = trialCounter + blockNtrials;
end




% % %   if isfield(cfg,'STIM_EPOCH')
% % %       % STIM EPOCH
% % %       stim_epoch = cfg.STIM_EPOCH;
% % %       stim_trig = cfg.STIM_TRIG;
% % %       stim_delay = cfg.STIM_DELAY;
% % %       stim_tl = cfg.STIM_TL;
% % %       idx = (1:length(stim_epoch))';
% % %       fac_stim_epoch_tbl = table(idx, stim_epoch, stim_trig, stim_delay, stim_tl); 
% % %       
% % %       % STIM FREQUENCY
% % %       stim_freq = cfg.STIM_FREQ;
% % %       idx = (1:length(stim_freq))';
% % %       fac_stim_freq_tbl = table(idx, stim_freq);
% % %       
% % %       % STIM LOCATION
% % %       stim_loc   = cfg.STIM_LOC;
% % %       stim_elec  = cfg.STIM_ELEC;
% % %       stim_amp   = cfg.STIM_AMP;
% % %       stim_label = cellfun(@(x) strjoin(x, ' & '),cfg.STIM_LABELS,'UniformOutput',false);
% % %       assert(length(cfg.STIM_LOC)==length(cfg.STIM_ELEC))
% % %       assert(length(cfg.STIM_LOC)==length(cfg.STIM_AMP))
% % %       assert(all(cellfun(@length, cfg.STIM_ELEC) == cellfun(@length, cfg.STIM_AMP)))
% % %       idx = (1:length(stim_loc))';
% % %       fac_stim_loc_tbl = table(idx, stim_loc, stim_amp, stim_elec, stim_label);
% % %       
% % %       % crossing stimulation epoch, frequency and location
% % %       factors_tbls = {fac_stim_epoch_tbl, fac_stim_freq_tbl, fac_stim_loc_tbl};
% % %       lens = cellfun(@(x) x.idx, factors_tbls, 'UniformOutput', false);
% % %       [a, b, c] = ndgrid(lens{:});
% % %       all_stim_tbl = table(a(:), b(:), c(:)); 
% % %       for ifac = 1:length(factors_tbls)
% % %           all_stim_tbl.idx = all_stim_tbl{:, ifac}; 
% % %           all_stim_tbl = join(all_stim_tbl, factors_tbls{ifac}, 'keys', 'idx');
% % %       end 
% % %       all_stim_tbl = all_stim_tbl(:,5:end);
% % %   else
% % %       all_stim_tbl = table();
% % %   end
% % % 
% % %   % adding no stim controls
% % %   if cfg.STIM_CTRL > 0 
% % %     ctrl_row =  table({'none'},     {'none'},    0,              0,         0,           {'none'},  {0},          {[]},        {''}, ...
% % %     'VariableNames', {'stim_epoch', 'stim_trig', 'stim_delay', 'stim_tl', 'stim_freq', 'stim_loc', 'stim_amp', 'stim_elec', 'stim_label'});
% % %     all_stim_tbl = [all_stim_tbl;repmat(ctrl_row,cfg.STIM_CTRL,1)];
% % %   end
% % %   all_stim_tbl.idx = (1:height(all_stim_tbl))';
% % % 
% % %   % crossing with sentences
% % %   factors_tbls = {stim_sentences, all_stim_tbl};
% % %   lens = cellfun(@(x) x.idx, factors_tbls, 'UniformOutput', false);
% % %   [a, b] = ndgrid(lens{:});
% % %   all_trials_tbl = table(a(:), b(:)); 
% % %   % combine factors idxs with information from factor tables
% % %   for ifac = 1:length(factors_tbls)
% % %       all_trials_tbl.idx = all_trials_tbl{:, ifac}; 
% % %       all_trials_tbl = join(all_trials_tbl, factors_tbls{ifac}, 'keys', 'idx');
% % %   end
% % % 
% % %   if isfield(cfg,'STIM_EPOCH')
% % %       % adding constant stimulation settings
% % %       all_trials_tbl.stim_pw1(:) = cfg.STIM_PW1;
% % %       all_trials_tbl.stim_pw_ratio(:) = cfg.STIM_PW_RATIO;
% % %       all_trials_tbl.stim_ipi(:) = cfg.STIM_IPI;
% % %       all_trials_tbl.stim_fs(:) = cfg.STIM_FS;
% % %       all_trials_tbl.stim_pl(:) = cfg.STIM_PL;
% % %       
% % %       % computing derived stimulation setings
% % %       
% % %       % The period at which to repeat stimulation in units of 33.3 μs (one clock cycle at 30 kHz).
% % %       all_trials_tbl.stim_period = round((1 ./ all_trials_tbl.stim_freq) ./ 0.0000333);
% % %       % The number of repetitions of the stimulation.
% % %       all_trials_tbl.stim_repeats= round((all_trials_tbl.stim_tl ./ 1000) ./ (all_trials_tbl.stim_period .* 0.0000333));
% % %       % Stimulation phase 1 length in units 33.3us
% % %       all_trials_tbl.stim_phase1_pw = round(all_trials_tbl.stim_pw1 ./ 33.3);
% % %       % phase 1 current amplitude
% % %       all_trials_tbl.stim_phase1_ampl =  cellfun(@(x) round(x ./ cfg.STIM_RES_mA), all_trials_tbl.stim_amp, 'UniformOutput', false); 
% % %       % Inter phase interval length in units 33.3us
% % %       all_trials_tbl.stim_phase_ipi = round(all_trials_tbl.stim_ipi ./ 33.3);
% % %       % Stimulation phase 2 length in units 33.3us
% % %       all_trials_tbl.stim_phase2_pw = round(all_trials_tbl.stim_pw1 .* all_trials_tbl.stim_pw_ratio ./ 33.3);
% % %       % phase current amplitude
% % %       all_trials_tbl.stim_phase2_ampl = cellfun(@(x,y) x * y, ...
% % %           all_trials_tbl.stim_phase1_ampl, ...
% % %           num2cell(all_trials_tbl.stim_phase1_pw ./ all_trials_tbl.stim_phase2_pw), ...
% % %           'UniformOutput',  false);
% % %       assert(all(mod([all_trials_tbl.stim_phase2_ampl{:}], 1) == 0), "Non integer ampl for phase 2. Check phase duration ratio");
% % %   
% % %   end
% % %   % randomize trials
% % %   all_trials_tbl = all_trials_tbl(randperm(height(all_trials_tbl)), :);
% % %   % ToDo: avoid same sentence twice in a row
% % %   % ToDo: create balance points throught the experiment for stim conditions
  
  % polish table 
%   dbTrials = all_trials_tbl(:, 4:end); 
%   dbTrials.trial_id = (1:height(dbTrials))';
%   dbTrials = movevars(dbTrials, 'trial_id', 'Before', 1); % move to leftmost column


