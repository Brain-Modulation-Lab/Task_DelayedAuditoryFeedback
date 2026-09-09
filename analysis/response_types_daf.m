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

% for defining nonwarped trial timecourse durations, use this much time before/after visual onset/offset
%%% this only affects how much data on each side gets saved for the purposes of plotting
field_default('op','trial_time_buffer',[1, 2.5]); % use 2 sec because subjects in DAF often keeep speaking for a while after visual offset

% consider electrodes responsive if they have above-baseline responses during one response epoch at this level
field_default('op','responsivity_alpha',0.05); % uncorrected
% field_default('op','responsivity_alpha',0.05 / 2^[3-1]); % bonf correction for 3 tests

%% Defining paths

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

% assign start and end times for nonwarped trial timecourses
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

%%% set up the config table for determining how to epoch ephys responses for this project
% NB: strongly recommended to not include any expected gaps between epochs, and have dur_fix('trial') equal to the sum of the durations of the other epochs
...... or else subsequent time labels on trial plots will likely be wrong
% all response values except 'base' are baseline-normalized by dividing by that trial's baseline average... 'base' records the absolute value of the baseline

epochs = table({'prebase';'base';'postbase';'stim';'prep';'speech';'postprod'},'VariableNames',{'epoch'});
epochs.Properties.RowNames = epochs.epoch;
epochs.onset = cell(height(epochs),1);
epochs.offset = cell(height(epochs),1);
epochs.dur_fix = nan(height(epochs),1); 
epochs.dur_fix('prebase') = 0.6;
    epochs.onset{'prebase'} = {'t_vis_stim_on',-1};          % pre-base buffer
    epochs.offset{'prebase'} = {'t_vis_stim_on',-0.5};
epochs.dur_fix('base') = 0.4;
    epochs.onset{'base'} = {'t_vis_stim_on',-0.5};          % 'base' = average during pre-visual-stim baseline
    epochs.offset{'base'} = {'t_vis_stim_on',-0.1};
epochs.dur_fix('postbase') = 0.1;
    epochs.onset{'postbase'} = {'t_vis_stim_on',-0.1};          % spacer between baseline and vis stim on
    epochs.offset{'postbase'} = {'t_vis_stim_on',0};
epochs.dur_fix('stim') = 2.6;
    epochs.onset{'stim'} = 't_vis_stim_on'; 
    epochs.offset{'stim'} = 't_aud_go_on'; % stim doesn't actually disappear until end of trial, but we end 'stim epoch' at gobeep
epochs.dur_fix('prep') = 0.8; % avg estimated speech reaction time
    epochs.onset{'prep'} = 't_aud_go_on'; 
    epochs.offset{'prep'} = 't_prod_on'; 
epochs.dur_fix('speech') = 5; % avg estimated speech duration
    epochs.onset{'speech'} = 't_prod_on'; 
    epochs.offset{'speech'} = 't_prod_off'; 
    epochs.early_overlap_allowed('speech') = true; % we allow the speech epoch to consume preceding epochs; we don't have enough trials to throw out early response trials
epochs.dur_fix('postprod') = 3.5;             % post speech epoch - look for beta rebound here
    epochs.onset{'postprod'} = {'t_prod_off',0}; 
    epochs.offset{'postprod'} = {'t_prod_off',2.5}; 
    
op.epochs = epochs; 

[resp, trials] = get_epoched_responses(D_wavpow,trials,op);


%% test for response types 
nchans = height(resp);
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
        [~, resp.p_prod(ichan)] = ttest2(resp.speech{ichan}(good_trials), zeros_vec); 

        % test for general task responsivity
        %%%% one way to make this metric more stringent would be: run anova on mean response in 4 periods: baseline, stim, prep, speech
        resp.p_min_stim_prep_prod(ichan) = min([resp.p_stim(ichan), resp.p_prep(ichan), resp.p_prod(ichan)]);
        resp.rspv(ichan) = resp.p_min_stim_prep_prod(ichan) < op.responsivity_alpha; 

         % preferential response for DAF delay... use anova to treat delay as categorical
        resp.p_stim_delay(ichan) = anova1(resp.stim{ichan}(good_trials),trials.delay(good_trials),'off');
        resp.p_prep_delay(ichan) = anova1(resp.prep{ichan}(good_trials),trials.delay(good_trials),'off');
        resp.p_prod_delay(ichan) = anova1(resp.speech{ichan}(good_trials),trials.delay(good_trials),'off');
   
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
resp = movevars(resp,{'base','timecourse','stim','prep','speech'},'After','HCPMMP1_weight_2');
resp = movevars(resp,{'sub','chan','HCPMMP1_label_1'},'Before',1);

% right DBS was not recorded during the SEQ task in these subjects but remained in the channels  table - remove these chans if they're present
resp = resp(~contains(resp.chan,'dbs_R'),:);

op_out = op; 

end


