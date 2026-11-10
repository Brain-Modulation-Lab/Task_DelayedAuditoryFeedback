 %%%% average event-synced responses of electrodes and plot; combine elcs within a region

  %%% load resp_all_subjects first
  % loaded data must include resp, subs, and op (which includes epoch table that was used for time warping)
% 
% paths = set_paths_daf(); load([paths.results, filesep, 'resp_all_subjects_beta.mat']) % load data
% paths = set_paths_daf(); load([paths.results, filesep, 'resp_all_subjects_hg.mat'])

% close all

op.newfig = 1; 

% inclusion params
op.analyze_responsive_elcs_only = 1; 
op.analyze_tuned_elcs_only = 0;

op.min_events_per_elc = 1;  % Minimum number of occurrences of a specific event type required for an electrode's average trace to be included in regional aggregation
op.min_elcs_per_region = 1; 



%% Trial condition for grouping trials
%     op.sort_cond = ''; % plot all trials averaged as a single timecourse without sorting
    op.sort_cond = 'delay';       op.sort_cond_vals = [0, 50, 228]; 

%% parameter for filtering out which electrodes to plot
% op.tuning_param = 'p_min_stim_prep_prod';

% op.tuning_param = 'p_stim'; 
% op.tuning_param = 'p_prep'; 
op.tuning_param = 'p_prod'; 

% op.tuning_param = 'p_stim_delay';
% op.tuning_param = 'p_prep_delay';
% op.tuning_param = 'p_prod_delay';

%% choose sync-events to plot traces for

% change so that each line lists columns of events table and then the value that must match in that column
%%% eg only sld repetitions that get resolved.... or asr events that have a fluent event ID..... or just write the rules for how we define traces here and give the trace a name

% cfg.event_types = {'sld_repetition','sld_prolongation','typical_disfluency','disfluency_resolution','error','slowing','distortion'};
% op.event_types = {'sld_repetition','sld_prolongation','slowing','error','disfluency_resolution'}; 
% op.event_types = {'sld_repetition','sld_prolongation','slowing','disfluency_resolution'}; 
% op.event_types = {'sld_prolongation','slowing'}; 
% op.event_types = {'sld_prolongation','typical_disfluency'}; 
op.event_types = {'sld_repetition','disfluency_resolution'}; 

% op.regions_to_plot  = {'SMC','IFG/IFS','Thal'};
op.regions_to_plot = {}; % plot all regions

% display params
op.sync_window_sec = []; % if empty, use the full window saved in resp table
op.smooth_windowsize_sec = 0.5; op.smooth_method = 'gaussian'; % Smoothing algorithm passed to MATLAB's smoothdata (e.g., 'gaussian', 'moving', 'lowess', 'sgolay').
op.event_colors = 'lines'; % Specifies the colormap name string (e.g., 'lines', 'parula', 'turbo') or an $N_{\text{events}} \times 3$ RGB matrix for custom event trace colors.
op.errorbar_alpha = 0.2; % Controls the transparency (FaceAlpha) of the shaded SEM error bar polygons.


%% ============ CALL MAIN FUNCTION ============
op.resptab_varname = 'disf'; % event-synced responses are in resp.disf and timing is in subs.disf
[synced_resp, op_out] = ...
    plot_event_synced_resp(resp, subs, op);