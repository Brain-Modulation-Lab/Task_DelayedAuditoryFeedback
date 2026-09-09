 %%%% average timecourses of electrodes and plot; combine elcs within a region

  %%% load resp_all_subjects first
  % loaded data must include resp, subs, and op (which includes epoch table that was used for time warping)
% 
% paths = set_paths_daf(); load([paths.results, filesep, 'resp_all_subjects_beta.mat']) % load data
paths = set_paths_daf(); load([paths.results, filesep, 'resp_all_subjects_hg.mat'])

% close all

op.newfig = 1; 

op.analyze_responsive_elcs_only = 1; 
op.analyze_tuned_elcs_only = 0;

op.smooth_windowsize = 75; 

%% Trial condition for grouping trials
%     op.sort_cond = ''; % plot all trials averaged as a single timecourse without sorting
    op.sort_cond = 'delay';       op.sort_cond_vals = [0, 50, 228]; 

%% parameter for filtering out which electrodes to plot
% op.tuning_param = 'p_min_stim_prep_prod';

% op.tuning_param = 'p_stim'; 
% op.tuning_param = 'p_prep'; 
% op.tuning_param = 'p_prod'; 

op.tuning_param = 'p_stim_delay';
% op.tuning_param = 'p_prep_delay';
% op.tuning_param = 'p_prod_delay';

%% Which epochs to label with text annotations?
% If empty: label all epochs
% If cell array: label only specified epochs
% op.epochs_to_label = {'base','stim', 'prep','speech'};  % Only show labels for these epochs
op.epochs_to_label = {'stim', 'prep','speech'};  % Only show labels for these epochs
% op.epochs_to_label = {};  % Alternative: label all epochs

% op.regions_to_plot  = {'SMC','IFG/IFS','Thal'};
op.regions_to_plot = {}; % plot all regions

%% Epoch visualization options
op.epoch_colors = parula(height(op.epochs));  % or 'viridis', 'turbo', 'hsv', etc.
op.epoch_alpha = 0.12;
op.epoch_label_height = 0.92;
op.epoch_label_fontsize = 8;

%% ============ CALL MAIN FUNCTION ============
[cond_elc_rgn, align_stats_rgn, resp_grpd_rgn, cfg_rgn] = ...
    combine_plot_electrode_timecourses(resp, subs, op);