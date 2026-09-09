  
%%%% plot electrodes meeting certain criteria on brain 

  %%% load resp_all_subjects first
% 
paths = set_paths_daf(); load([paths.results, filesep, 'resp_all_subjects_beta.mat'])
% paths = set_paths_daf(); load([paths.results, filesep, 'resp_all_subjects_hg.mat'])


%% parameter for filtering out which electrodes to plot
op.tuning_param = 'p_min_stim_prep_prod';
%
% op.tuning_param = 'p_stim_delay';
% op.tuning_param = 'p_prep_delay';
% op.tuning_param = 'p_prod_delay';


op.inclusion_mode = 'thresh';
    op.include_thresh = 0.05; 
% op.inclusion_mode = 'proportion';
%     op.include_proportion = 0.1; 

brainplot_top_electrodes(resp,op);