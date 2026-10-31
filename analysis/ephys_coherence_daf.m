
%%%% do coherence analysis for subjects in daf and compile pairs into a single table
% you must run batch_response_types_daf first to generate the subs table (covers all subs) and resp.rspv (specific to each sub)
%
% 

clear

 % most important is rsvp … maybe also p prod learn prep stim, p prod prep stim, p syl stim prep prod
op.resp_vars_to_copy = {'rspv','bad_elc','p_min_stim_prep_prod',...
    'p_stim','p_prep','p_prod', ...
    'p_stim_delay','p_prep_delay','p_prod_delay', ...
    }; 

op.sort_cond = 'delay'; op.sort_cond_vals = {0 50 228}; 


% % % % % % analyze coherence at these freq bands
% op.freqs = [20, 100]; 
% op.freqs = [100]; 
% op.freqs = round(logspace(log10(70), log10(150), 6)); 
op.freqs = round(logspace(log10(1), log10(150), 50),1); 

% analyze coherence between these regions
op.regions_to_analyze = {'SMC','IFG/IFS','MFG','Thal'}; 
% op.regions_to_analyze = {'OFC','Thal'}; 


event = {'t_prod_on'}; 
    sync_events = table(event,nan(size(event)),nan(size(event)),'VariableNames',{'event','start','end'},'RowNames',event); clear event
sync_events{'t_prod_on','start'} = -4; % start about at baseline start
    sync_events{'t_prod_on','end'} = 7; % end of trial, including time for beta baseline rebound


op.fieldtrip_var_name = 'D_ref'; % variable name of the fieldtrip struct variable `

op.coh_measure = 'mag_sq'; % 'mag_sq' (magnitude square) or 'imag' (imaginary part)
op.buffer_window_sec = 1; % 1 sec buffer around windows to avoid edge artifacts during time-frequency decomposition

 op.show_progress = 1; % if true, do commandline output when proceeding to new subject with/ subject name

%% create subs table with necessary paths

paths = set_paths_daf(); 
subs_processed_file = fullfile(paths.results, 'resp_all_subjects_hg.mat'); 
op.savefile = fullfile(paths.results, 'coh_all_subjects.mat'); 
op.sync_events = sync_events; 

load(subs_processed_file, 'subs'); % may take a few seconds because this file also contains large resp table which we are not loading


nsubs= height(subs);
for isub = 1:nsubs
    subs.paths{isub}.fieldtrip = subs.paths{isub}.fieldtrip_ref; % specify which fieldtrip file to use for coherence analysis
    subs.paths{isub}.artifact = subs.paths{isub}.artifact_manual; % specify which artifact file to use for coherence analysis
%     subs.paths{isub}.trials = subs.paths{isub}.trials_beh;  % specify which trials file to use for coherence analysis
end

% subs = subs(1,:);

%%


coh = ephys_coherence(subs, op) 

%% plotting example pair
pair_row = 10;
sync_ind = 1; 

% --- TOGGLE SCALE MODE HERE ---
% Choices: 'equal' (log-like index scale assuming y spacing is log) or 'linear' (true frequency spacing)
% yscale_mode = 'linear'; 
yscale_mode = 'equal'; 


sync_event = 't_prod_on'; 
coh1 = coh.coh{pair_row}; 
xtime = coh1.time{sync_ind};
tcon = coh1.trialconds{sync_event}; 
ncon = height(tcon);  

close all
hfig = figure('WindowState', 'maximized');

tcon.Properties.RowNames = strrep(tcon.Properties.RowNames,'cond_','');
if isnumeric(tcon.cond{1})
    tcon.cond = cellfun(@num2str,tcon.cond,'UniformOutput',false);
end

for icon = 1:ncon
    subplot(1, ncon, icon)
    coh_data = tcon{tcon.cond{icon}, 'freqs'}{1}.coh; 
    plotfreqs = tcon{tcon.cond{icon}, 'freqs'}{1}.freq; 
    hax = gca;
    
    switch yscale_mode
        case 'equal'
            % 1. EQUAL HEIGHTS MODE (Natively stretches rows equally)
            imagesc(xtime, 1:length(plotfreqs), coh_data);
            axis xy;
            
            % Automatically pick 8 evenly spaced row indices for labels
            tick_idx = round(linspace(1, length(plotfreqs), 8)); 
            hax.YTick = tick_idx;
            hax.YTickLabel = string(round(plotfreqs(tick_idx), 1));
        
        case 'linear'
            % 2. TRUE LINEAR SCALE MODE (Row heights match frequency gaps)
            % pcolor draws a checkerboard grid using the true coordinates
            hp = pcolor(xtime, plotfreqs, coh_data);
            shading flat; % Removes the black grid lines between pixels
            axis xy;
            
            % Let MATLAB handle the numeric ticks naturally for linear spacing
            hax.YTickMode = 'auto';
            hax.YTickLabelMode = 'auto';
        otherwise
            error('unknown scale mode')
    end
    
    axis tight
    title(tcon.cond{icon})
    ylabel('Frequency (Hz)')
    xlabel(['Time after ', sync_event, ' (s)'])
end




