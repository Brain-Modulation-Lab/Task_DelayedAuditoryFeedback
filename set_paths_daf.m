
function [paths, compname] = set_paths_daf(op,paths)

%% setup
% if a paths variable wasn't provided, create a new one
if ~exist('paths','var')
    paths = struct; 
end

compname = getenv('COMPUTERNAME'); % might not work on non-windows machines


%% determine which computer and set appropriate paths
if strcmp(compname,'BML-ALIENWARE2') % intraop/prep rig - task computer, no analysis to be done - add only minimal paths
        add_analysis_paths = 0; 
        paths.task       = 'D:\Task\Task_DelayedAuditoryFeedback';
        paths.data = 'D:\DBS'; 
        paths.sourcedata = 'D:\DBS\sourcedata';
        analayis_paths = {};

else % analysis computers - need to add more paths
     add_analysis_paths = 1; 
    
    switch compname
        case {'677-GUE-WL-0010','677-GUE-WL-0012','AMSMEIER'}  % AM Thinkpad X1 laptops, strix laptop
            paths.code = 'C:\docs\code'; 
            paths.data = 'Y:\DBS'; % mapped drive
            paths.task       = [paths.code, filesep, 'Task_DelayedAuditoryFeedback']; 
            paths.bml = [paths.code, filesep, 'bml']; % RM Richardson lab toolbox

        case    'NSSBML01' % Turbo - used via remote desktop protocol
            paths.code = 'Y:\Documents\Code'; 
            paths.task = [paths.code, filesep, 'Task_DelayedAuditoryFeedback']; 
            paths.data = 'Y:\DBS'; % mapped drive
            paths.bml = 'C:\Program Files\Brain-Modulation-Lab\bml'; 


    otherwise 
        error('unknown computer')
    end

    %% common paths for analysis

    paths.analysis_code = [paths.task, filesep, 'analysis']; % code for daf task analysis

    % data paths
     paths.der = [paths.data filesep 'derivatives'];
     paths.src = [paths.data filesep 'sourcedata'];
     paths.results = [paths.data, filesep, 'groupanalyses', filesep, 'task-daf'];
% % % % %      PATH_SUB_MASTER_TABLE = 
% % % %      PATH_STIM_INFO_TABLE = [paths.task, filep]; 

    % external toolboxes
     paths.ieeg_ft_funcs_am = [paths.code filesep 'ieeg_ft_funcs_am']; % ieeg processing code shared across AM projects
    paths.fieldtrip_code = [paths.ieeg_ft_funcs_am, filesep, 'preprocessing', filesep, 'fieldtrip-master-rd'];  % modified version for optimized filter functions for preprocessing     
     paths.spm = [paths.code, filesep, 'spm12']; %%%% 

    % add these paths only if we are not on the intraop rig computer
     analayis_paths =  {paths.task;...
        paths.analysis_code;...
         [paths.task, filesep, 'util'];...
        % paths.spm;... %%%% 
        paths.fieldtrip_code;... % needed for preproc step A04
        paths.ieeg_ft_funcs_am;...
        [paths.ieeg_ft_funcs_am, filesep, 'preprocessing'];...
        paths.bml
    };
%%

end

%% add to the matlab path from the list we created
paths.sourcedata = [paths.data, filesep, 'sourcedata']; 
paths.stim = [paths.task, filesep, 'stimuli'];
paths.code_exp_scripts = [paths.task, filesep, 'scripts'];
paths.code_analysis = [paths.task, filesep, 'analysis'];

% paths to add regardless of computer
paths_to_add = [analayis_paths;...
    paths.task;...
    paths.stim;...
    paths.code_exp_scripts;...
    ];

 addpath(paths_to_add{:});



if add_analysis_paths

    %% for analysis -  make sure that we don't have any unintended fieldtrip folders in our path
    if length(which('-all', 'ft_preprocessing')) > 1 % if there's an extra copy of fieldtrip on path, get rid of them all
        while ~isempty(which('-all', 'ft_preprocessing'))
            rmpath(genpath(fileparts(which('ft_defaults'))))
        end
    
        addpath(paths.fieldtrip_code); % re-add correct path
    end
    
    % if ft_defaults hasn't been run in this session or needs to be rurn, run it
    if ~contains(path,[paths.fieldtrip_code, filesep, 'connectivity'])
        ft_defaults()
    end
    
    % if bml_defaults hasn't been run in this session or needs to be rurn, run it
    if ~contains(path,[paths.bml, filesep, 'anat'])
        bml_defaults()
    end
    
    addpath(fileparts(which('anova1'))); % make sure Matlab stats toolbox is on top, so that it's not superseded by fieldtrip/external/stats
    
    set(0, 'DefaultTextInterpreter', 'none')
    set(0, 'DefaultLegendInterpreter', 'none')
    set(0, 'DefaultAxesTickLabelInterpreter', 'none')
    format long
    
    
    
    %% if more details are provided (e.g. subject), output relevant paths
    % these are only for later referenc - don't add them to the matlab path
    if exist('op','var')
        if isfield(op,'sub') % if sub specified
            paths.src_sub = [paths.data, filesep,'sourcedata', filesep, 'sub-',op.sub]; 
            paths.der_sub = [paths.data, filesep, 'derivatives', filesep, 'sub-',op.sub]; 
            paths.annot = [paths.der_sub, filesep, 'annot']; 
            paths.runs_table = [paths.annot, filesep, 'sub-',op.sub, '_runs.tsv'];
            % paths.landmarks_file = [paths.annot filesep, ]; 
            paths.trial_audio = [paths.der_sub, filesep, 'trial-audio']; 
            paths.preproc = [paths.der_sub, filesep, 'preproc']; 
            paths.fieldtrip_data = [paths.der_sub, filesep, 'fieldtrip']; 
            paths.electrodes = [paths.annot, filesep, 'sub-',op.sub, '_electrodes.tsv']; 
    
            if isfield(op,'ses') % if session specified
                paths.src_ses = [paths.src_sub, filesep,'ses-',op.ses]; 
                paths.src_task = [paths.src_ses, filesep, 'task'];
                paths.src_audio = [paths.src_ses, filesep, 'audio'];
                paths.der_annot_trials = [paths.annot, filesep, 'sub-',op.sub, '_ses-',op.ses, '_task-',op.task, '_annot-trials.tsv']; 
                paths.trials_beh = [paths.annot, filesep, 'sub-',op.sub, '_ses-',op.ses, '_task-',op.task, '_trials-beh.mat']; % behavioral annotations; .mat and not tsv because of complex data types
                paths.trials_audiofiles = [paths.trial_audio, filesep, 'sub-',op.sub, '_ses-',op.ses, '_task-',op.task, ...
                    '_recording-directionalmic_physio_audiofiles.tsv'];
                paths.landmarks_file = [paths.annot filesep 'sub-' op.sub, '_ses-', op.ses,  '_annot-audio-landmarks.tsv']; 
                paths.sync_ses = [paths.annot, filesep, 'sub-',op.sub, '_ses-',op.ses, '_sync.tsv']; 
                paths.artifact_manual = [paths.annot, filesep, 'sub-',op.sub, '_ses-',op.ses, '_task-',op.task, '_artifact-manual.tsv'];  
                paths.ft_file_prefix = [paths.fieldtrip_data, filesep, 'sub-', op.sub, '_ses-' op.ses '_task-' op.task, '_ft-']; % string (including filepath) at beginning of all fieldtrip filenames for this subject
    
                    if isfield(op,'run') % if run specified
                        if ischar(op.run)
                            op.runstr = op.run;
                            op.run = str2double(op.runstr); 
                        elseif isnumeric(op.run)
                            op.runstr = sprintf('%02.0f', op.run); % expect run string as 2 digits; zero pad
                        else
                            error('unrecognized run label format - should be string or number')
                        end
    
                        %%%% the following string gets used in a variety of files associated with this run
                        paths.filestr = ['sub-',op.sub, '_ses-',op.ses, '_task-daf_run-',num2str(op.runstr), '_']; 
                        
                        % trial boundary adjustments - gets created during create_sync_landmark_tables.m
                        % .... gets used during audio/video trial cutting
                        %%% note that these adjustments will not change any subsequent statistical analyses....
                        %%% ... they change where the trial-wise audio/video files will be cut to make it easier to do annotations
                        %%% generally this will be useful for when the sub answers early and you want the file to start earlier
                        paths.trialfile_boundary_adjustments = [paths.trial_audio, filesep, paths.filestr, 'boundary_adjustments.tsv'];
    
                    end
            end
        end
    end
end