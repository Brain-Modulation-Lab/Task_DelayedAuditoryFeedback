 
 %%%% average timecourses of electrodes and plot

  %%% load resp_all_subjects first
% paths = set_paths_daf()
% load([paths.results, filesep, 'resp_all_subjects_beta.mat'])
% load([paths.results, filesep, 'resp_all_subjects_hg.mat'])

close all

op.newfig = 1; 

op.analyze_responsive_elcs_only = 1; 
op.analyze_tuned_elcs_only = 0;

op.smooth_windowsize = 45; 

%% trial condition for grouping trials

%     op.sort_cond = ''; % plot all trials averaged as a single timecourse without sorting
    op.sort_cond = 'delay';       op.sort_cond_vals = [0, 50, 228]; 

%% parameter for filtering out which electrodes to plot
op.tuning_param = 'p_stim_delay';
% op.tuning_param = 'p_prep_delay';
% op.tuning_param = 'p_prod_delay';








%% trial table varname for times used for time-locking responses
% op.time_align_var = 't_vis_stim_on'; % audio stim cue on
% op.time_align_var = 't_aud_go_on'; % go beep
% op.time_align_var = 't_prod_on'; % speech onset
op.time_align_var = 't_prod_off'; % speech onset


op.xline_events = {'t_vis_stim_on','t_vis_stim_on','t_aud_go_on','t_prod_on','t_prod_off'};
op.include_xline_for_align_event = 1; 

op.leg_pos_adjust = -0.04; % legend hrz position
op.xline_event_label_height = .9; 

op.xline_events(2,:) = relabel_events_daf(op.xline_events); % specify display labels



% subs.trials{1}(1:5:end,:) = []; % get rid of first trial of miniblock whe they don't know the condition

[cond_elc_rgn, align_stats_rgn, resp_grpd_rgn, cfg_rgn] = combine_plot_electrode_timecourses(resp,subs,op);