% compute eletrode responses during specific trial epochs
% look for electrodes with different responses to different conditions
%
% required parameters for 'op' struct: sub
%
% for daf task, divide trial into 3 periods: 
... stim (after vis stim onset, before go beep)
... prep (after go beep, before speech onset)
... speech (after speech onset, before speech offset)

function [resp, trials, op_out] = response_types_daf(op)

%% analysis parameters

%%%% for baseline window, use the period from -op.base_win_sec(1) to -op.base_win_sec(2) before visual stim onset.... this comes before aud stim onset in dbsseq
%%% baseline should end at least a few 100ms before visual stim onset in order to not include anticipatory activity in baseline
field_default('op','base_win_sec', [0.5, 0.1]); % 
field_default('op','stim_window_extend_end', 0.3); % for responses during stimulus, add this long in seconds to the analyzed 'stimulus period' after actual stim offset

% for responses during speech, start the analyzed 'speech period' this early in seconds to capture pre-sound muscle activation; also end prep period this early
field_default('op','speech_window_extend_start', 0.15);  

% for defining trial durations, use this much time before/after visual onset/offset
%%% this only affects how much data on each side gets saved for the purposes of plotting
field_default('op','trial_time_buffer',[1, 2.5]); % use 2 sec because subjects in DAF often keeep speaking for a while after visual offset

% consider electrodes responsive if they have above-baseline responses during one response epoch at this level
field_default('op','responsivity_alpha',0.05); % uncorrected
% field_default('op','responsivity_alpha',0.05 / 2^[3-1]); % bonf correction for 3 tests

%% Defining paths, loading parameters

field_default('op','resp_signal','hg'); 
field_default('op','baseline_method','subtract_then_divide'); % options: 'divide_then_subtract','subtract'
field_default('op','max_timecourse_base_ratio',50); % in each trial, if ratio of timecourse avg to baseline is higher than this, exclude the trial

op.ses = 'intraop';
op.task = 'daf'; 

paths = set_paths_daf(op); % get subject-specific filepaths

%% load data 
load([paths.ft_file_prefix, op.resp_signal, '.mat'],'D_wavpow')

% % trial timing and electrode info
trials = load(paths.trials_beh);  trials = trials.trials_beh; 
electrodes_table_filename = [paths.annot filesep 'sub-' op.sub '_electrodes.tsv'];

% assign start and end times
trials.starts = trials.t_vis_stim_on - op.trial_time_buffer(1);
trials.ends = trials.t_vis_stim_off + op.trial_time_buffer(2); 

if exist(electrodes_table_filename, 'file')
    elc_info_raw = bml_annot_read_tsv([paths.annot filesep 'sub-' op.sub '_electrodes.tsv';]); 
        elc_info_raw = renamevars(elc_info_raw,'name','chan');
else
    channels = bml_annot_read_tsv([paths.annot filesep 'sub-' op.sub '_ses-' op.ses '_channels.tsv']); %%%% for connector info
        channels.name = strrep(channels.name,'_Ll','_Lm'); % change name to match naming convention in electrodes table
    channels(channels.connector==0,:) = []; % channels with this connector label seem to be duplicates or unused
    elc_info_raw = channels; 
    elc_info_raw = renamevars(elc_info_raw,'name','chan');

    % fill in blank info for localization variables if electrodes table is not available
    nancol = nan(height(elc_info_raw),1); 
    celcol = cell(height(elc_info_raw),1); 
    elc_info_blank = table(...
        nancol, nancol, nancol, ...
        nancol, nancol, nancol, ...
        celcol, nancol, celcol, nancol, celcol, nancol, ...
        celcol, nancol,celcol, nancol, ...
        'VariableNames',...
        {'native_x','native_y','native_z',...
        'mni_x','mni_y','mni_z',...
	    'DISTAL_label_1','DISTAL_weight_1','DISTAL_label_2','DISTAL_weight_2','DISTAL_label_3','DISTAL_weight_3',...
        'HCPMMP1_label_1','HCPMMP1_weight_1','HCPMMP1_label_2','HCPMMP1_weight_2'}); 
    elc_info_raw = [elc_info_raw, elc_info_blank];
end

% rename dbs channels to match bipolar reref 'channels'
dbs_elc_names = {'dbs_L1','dbs_L2A','dbs_L2B','dbs_L2C','dbs_L3A','dbs_L3B','dbs_L3C','dbs_L4'};
dbs_bipolar_chan_names = {'dbs_L1-L2','dbs_L2A-B','dbs_L2B-C','dbs_L2C-A','dbs_L3A-B','dbs_L3B-C','dbs_L3C-A','dbs_L4-L3'};
mapElcToChan = containers.Map(dbs_elc_names, dbs_bipolar_chan_names);
elc_info = elc_info_raw; 
for i = 1:numel(elc_info.chan)
    if isKey(mapElcToChan, elc_info.chan{i})
        elc_info.chan{i} = mapElcToChan(elc_info.chan{i});
    end
end


%% get responses in predefined epochs
% 'base' = average durng pre-visual-stim baseline
% all response values except 'base' are baseline-normalized by dividing by that trial's baseline average... 'base' records the absolute value of the baseline
ntrials = height(trials);
nchans = length(D_wavpow.label);
nans_ch = nan(nchans,1); 
nans_tr = nan(ntrials,1); 
cel_tr = cell(ntrials,1); 

% table containing responses during epochs for each chan
cel = repmat({nans_tr},nchans,1); % 1 value per trial per chan
resp = table(   D_wavpow.label, cel,   repmat({cel_tr},nchans,1),  cel,    cel,    cel,  ....
  'VariableNames', {'chan', 'base', 'timecourse',             'stim', 'prep', 'prod'}); 

% extract epoch-related responses, get phonemes on each trial
%%%% trials.times{itrial} use global time coordinates
%%%% ....... start at a fixed baseline window before stim onset
%%%% ....... end at a fixed time buffer after speech offset
for itrial = 1:ntrials % itrial is absolute index across sessions; does not equal "trial_id" from loaded tables

    % get indices within the trial-specific set of timepoints of D_wavpow.time{1} that match our specified trial window
    match_time_inds = D_wavpow.time{1} > trials.starts(itrial) & D_wavpow.time{1} < trials.ends(itrial); 
    trials.times{itrial} = D_wavpow.time{1}(match_time_inds); % times in this trial window... still using global time coordinates

    % get trial-relative baseline time indices; window time-locked to first stim onset
    base_inds = D_wavpow.time{1} > [trials.t_vis_stim_on(itrial) - op.base_win_sec(1)] & ... % times after base window starts
                D_wavpow.time{1} < [trials.t_vis_stim_on(itrial) - op.base_win_sec(2)];      % times before base window ends
    stim_inds = D_wavpow.time{1} > trials.t_vis_stim_on(itrial) & ...   % times after vis onset
                D_wavpow.time{1} < trials.t_aud_go_on(itrial);          % before go beep onset
    prep_inds = D_wavpow.time{1} > trials.t_aud_go_on(itrial) & ...                             % times after go beep onset
                D_wavpow.time{1} < [trials.t_prod_on(itrial) - op.speech_window_extend_start];  % times before speech window
    prod_inds = D_wavpow.time{1} > [trials.t_prod_on(itrial) - op.speech_window_extend_start]   & ...  % times before speech window start
                D_wavpow.time{1} < trials.t_prod_off(itrial);                                          % times before speech offset

    for ichan = 1:nchans
        % baseline activity and timecourse
        % use mean rather than nanmean, so that trials which had artifacts marked with NaNs will be excluded
        resp.base{ichan}(itrial) = mean( D_wavpow.trial{1}(ichan, base_inds), 'includenan' ); % mean wavpow during baseline

        % set up params for baselining
        cfg = [];
        cfg.baseval = resp.base{ichan}(itrial); 
        cfg.method = op.baseline_method; 
    
        % get baseline-normalized trial timecourse
       resp.timecourse{ichan}{itrial} = do_baselining(D_wavpow.trial{1}(ichan, match_time_inds), cfg); 


       %%% if response looks artifactually high, set/leave all response values for this trials to nan
       if max(resp.timecourse{ichan}{itrial}) > op.max_timecourse_base_ratio
           resp.timecourse{ichan}{itrial} = nan(size(resp.timecourse{ichan}{itrial}));
       else 
            % response during stim presentation, before go beep
            resp.stim{ichan}(itrial) = do_baselining(mean( D_wavpow.trial{1}(ichan, stim_inds) ), cfg);
    
            % preparatory response
            %%%% prep period inds = after go beep, before speech window start
            resp.prep{ichan}(itrial) = do_baselining(mean( D_wavpow.trial{1}(ichan, prep_inds) ), cfg);
    
            % response during speech production
            resp.prod{ichan}(itrial) = do_baselining(mean( D_wavpow.trial{1}(ichan, prod_inds) ), cfg);
       end
    end    
end

%% test for response types 
resp.bad_elc = cellfun(@(x)all(isnan(x)),resp.base);
for ichan = 1:nchans
    good_trials = ~isnan(resp.base{ichan}) & resp.base{ichan} ~= 0; % non-artifactual, non-zero-base trials for this channel
    good_trials = good_trials & ~trials.unusable_trial;
    zeros_vec = zeros(nnz(good_trials),1); 
    zeros_vec_gotrials = zeros(nnz(good_trials),1); 
    if nnz(good_trials) > 1 % only do stats analysis if channel had >0 good go trials
        % above/below-baseline response during the stim period
        [~, resp.p_stim(ichan)] = ttest2(resp.stim{ichan}(good_trials), zeros_vec_gotrials); 

        % above/below-baseline response during the prep period
        [~, resp.p_prep(ichan)] = ttest2(resp.prep{ichan}(good_trials), zeros_vec); 
    
        % above/below-baseline response during the production period
        [~, resp.p_prod(ichan)] = ttest2(resp.prod{ichan}(good_trials), zeros_vec); 

        % test for general task responsivity
        %%%% one way to make this metric more stringent would be: run anova on mean response in 4 periods: baseline, stim, prep, speech
        resp.p_min_stim_prep_prod(ichan) = min([resp.p_stim(ichan), resp.p_prep(ichan), resp.p_prod(ichan)]);
        resp.rspv(ichan) = resp.p_min_stim_prep_prod(ichan) < op.responsivity_alpha; 

         % preferential response for DAF delay... use anova to treat delay as categorical
        resp.p_stim_delay(ichan) = anova1(resp.stim{ichan}(good_trials),trials.delay(good_trials),'off');
        resp.p_prep_delay(ichan) = anova1(resp.prep{ichan}(good_trials),trials.delay(good_trials),'off');
        resp.p_prod_delay(ichan) = anova1(resp.prod{ichan}(good_trials),trials.delay(good_trials),'off');
   
    end
end
    
%% cleanup
elec_info_overlapping_resptable = elc_info(ismember(elc_info.chan,resp.chan),:); % include only electrodes analyzed for this task

% add the following variables to the electrodes response table... use 'electrode' as key variable
info_vars_to_copy = {'chan','type','native_x','native_y','native_z',...
    'mni_x','mni_y','mni_z',...
	'DISTAL_label_1','DISTAL_weight_1','DISTAL_label_2','DISTAL_weight_2','DISTAL_label_3','DISTAL_weight_3',...
    'HCPMMP1_label_1','HCPMMP1_weight_1','HCPMMP1_label_2','HCPMMP1_weight_2'};
resp = join(resp, elec_info_overlapping_resptable(:,info_vars_to_copy)); % add elc_info to resp
resp.sub = cellstr(repmat(op.sub, nchans, 1));
resp = movevars(resp,{'base','timecourse','stim','prep','prod'},'After','HCPMMP1_weight_2');
resp = movevars(resp,{'sub','chan','HCPMMP1_label_1'},'Before',1);

% right DBS was not recorded during the SEQ task in these subjects but remained in the channels  table - remove these chans if they're present
resp = resp(~contains(resp.chan,'dbs_R'),:);

op_out = op; 

end

%%%% takes a response (numerical array) and does baseline normalization used a specified method
function normed_response = do_baselining(response,cfg)
    switch cfg.method
        case 'subtract'
            normed_response = response - cfg.baseval; 

        case 'subtract_then_divide'
            normed_response = [response - cfg.baseval] / cfg.baseval; 
    end
end

