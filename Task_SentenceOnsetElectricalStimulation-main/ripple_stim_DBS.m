function [onset, duration] = ripple_stim_DBS(cfg,iTrial)

if ~cfg.DIGOUT
    onset  = nan;
    duration = nan;
    fprintf(2,['\n***************************************',...
             '\n** Ripple system NOT found! DRY RUN! **',...
             '\n***************************************\n']);
    return;
end

%grouping electrodes based on position in blocks of 16 channels of the FEs
%macro+stim FEs can only stim on one channel per group of 16
FEb = ceil(iTrial.stim_elec/16); %Front End bank
unique_vals = unique(FEb);
stimgroup = zeros(size(FEb));
for i = 1:length(unique_vals)
    indices = find(FEb == unique_vals(i));
    stimgroup(indices) = 1:length(indices);
end

%iTrial = table2struct(dbTrials(5,:))
 unique_stimgroups = unique(stimgroup);
for i = 1:length(unique_stimgroups)
    stimgroup_elecs = iTrial.stim_elec(stimgroup == unique_stimgroups(i));
    stimgroup_phase1_ampl = iTrial.stim_phase1_ampl(stimgroup == unique_stimgroups(i));
    stimgroup_phase2_ampl = iTrial.stim_phase2_ampl(stimgroup == unique_stimgroups(i));
    clear X;
    for j = 1:length(stimgroup_elecs)
        cmd = [];
        cmd = struct('elec', stimgroup_elecs(j), ...
                      'period', iTrial.stim_period, ...
                      'repeats', iTrial.stim_repeats, ...
                      'action', 'immed');
        cmd.seq(1) = struct('length', iTrial.stim_phase1_pw, ...
                             'ampl', stimgroup_phase1_ampl(j), ...
                             'pol', iTrial.stim_pl, ...
                             'fs', 0, ...
                             'enable', 1, ...
                             'delay', 0, ...
                             'ampSelect', 1);
        cmd.seq(2) = struct('length', iTrial.stim_phase_ipi, ...
                             'ampl', 0, ...
                             'pol', 0, ...
                             'fs', 0, ...
                             'enable', 0, ...
                             'delay', 0, ...
                             'ampSelect', 1);
        cmd.seq(3) = struct('length', iTrial.stim_phase2_pw, ...
                             'ampl', stimgroup_phase2_ampl(j), ...
                             'pol', 1-iTrial.stim_pl, ...
                             'fs', 0, ...
                             'enable', 1, ...
                             'delay', 0, ...
                             'ampSelect', 1);
    
        X(j) = cmd;
    end

    % Send the stimulation
    if i==1
        onset = GetSecs; 
        duration = iTrial.stim_tl/1000; 
    end
    xippmex('stimseq', X);
    WaitSecs(0.000600); %delay to avoid conflicts with Ripple 
end


%     % Send the stimulation
%     if j==1
%         onset = GetSecs; 
%         duration = iTrial.stim_tl/1000; 
%     end
%     xippmex('stimseq', cmd);
%     WaitSecs(0.000600);
%     % WaitSecs( ((iTrial.stim_phase1_pw + iTrial.stim_phase2_pw + iTrial.stim_phase_ipi) + 5) * 0.0000333)
% 
% end


