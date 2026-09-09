%%%% plot timecourses of example electrodes
% run sort_top_tuned_daf first to create resp table

function plot_sample_timecourses_daf(resp,subs,op)

vardefault('op',struct);

%% params

field_default('op','rowlist',1:25);

% ylimits = []; % use defaults
% ylimits = [-1 2]; 

% xlimits = []; % use defaults
% xlimits = [-3 1.6]; 


nplotrows = 5; 

%     op.sort_cond = ''; % plot all trials averaged as a single timecourse without sorting
    op.sort_cond = 'delay';

op.condval_inds_to_plot = []; % plot all conditions

%%%%% trial table varname for times used for time-locking responses
% op.time_align_var = 't_vis_stim_on'; % audio stim cue on
% op.time_align_var = 't_aud_go_on'; % go beep
op.time_align_var = 't_prod_on'; % speech onset
% op.time_align_var = 't_prod_off'; % speech onset



op.smooth_timecourses = 1; 
    % op.smooth_method = 'movmean';
    op.smooth_method = 'gaussian';
    op.smooth_windowsize = 30; 

op.leg_pos_adjust = 0.21; % move legend position to the left this much... 0.21 looks good when using 2 columns
op.trace_width = 1; 
op.newfig = 0;
op.plot_raster = 0; 


op.xline_events = {'t_vis_stim_on','t_vis_stim_on','t_aud_go_on','t_prod_on','t_prod_off'};
op.include_xline_for_align_event = 1; 

op.leg_pos_adjust = -0.04; % legend hrz position
op.xline_event_label_height = .9; 
op.xline_event_label_font_size = 5; 

op.xline_events(2,:) = relabel_events_daf(op.xline_events); % specify display labels

%%%%%%%%%% if using the options below, make sure all elcs are from same sub or trial times will be incorrect

%%
nelcs = length(op.rowlist);

% close all
hfig = figure('WindowState','maximized','Color','w'); box off

for ielc = 1:nelcs
    resp_row_ind = op.rowlist(ielc) ;
    resp_tbl_row = resp(resp_row_ind,:); 

    subind = find(string(subs.sub) == resp_tbl_row.sub{1});
    trials_tmp = subs.trials{subind}; % temporary copy of trials table

    subplot(nplotrows,ceil(nelcs/nplotrows),ielc);
    [trials,resp_grpd, align_stats, op_out] = plot_resp_timecourse_daf(resp_tbl_row,trials_tmp,op); % in ieeg_ft_funcs_am repo

%     if ~isempty(ylimits)
%         ylim(ylimits)
%     end
%     if ~isempty(xlimits)
%         xlim(xlimits)
%     end

end

 