
function [paths, compname] = set_paths_daf(op,paths)

% if a paths variable wasn't provided, create a new one
if ~exist('paths','var')
    paths = struct; 
end

compname = getenv('COMPUTERNAME'); % might not work on non-windows machines
    compname = deblank(compname); 
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % auddevs = audiodevinfo; 
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     devs_in = {auddevs.input.Name};
% % % % % % % % % % % % % % % % % % % % % % % % % % % % %     devs_out = {auddevs.output.Name};

    switch compname
        case 'BML-ALIENWARE2' % intraop/preop rig laptop
            paths.task       = 'D:\Task\Task_DelayedAuditoryFeedback';
            paths.data = 'D:\DBS'; 
            paths.sourcedata = 'D:\DBS\sourcedata';
        case {'677-GUE-WL-0010','677-GUE-WL-0012','AMSMEIER'}  % AM Thinkpad X1 laptops, strix laptop
            paths.code = 'C:\docs\code'; 
            paths.data = 'Y:\DBS'; % mapped drive
            paths.task       = [paths.code, filesep, 'Task_DelayedAuditoryFeedback']; 

            % external toolboxes
            paths.spm = [paths.code, filesep, 'spm12']; %%%% 
            paths.fieldtrip_toolbox = [paths.code, filesep, 'fieldtrip']; % only used in analysis, not running experiment
            paths.bml = [paths.code, filesep, 'bml']; % RM Richardson lab toolbox

            % add these paths only if we are not on the intraop rig computer
             paths_to_add =  {paths.task;...
                 [paths.task, filesep, 'util'];...
                % paths.spm;... %%%% 
                % paths.fieldtrip_toolbox;...
                paths.bml
            };

        otherwise 
            error('unknown computer')
    end

paths.sourcedata = [paths.data, filesep, 'sourcedata']; 
paths.stim = [paths.task, filesep, 'stimuli'];
paths.code_exp_scripts = [paths.task, filesep, 'scripts'];
paths.code_analysis = [paths.task, filesep, 'analysis'];

% paths to add regardless of computer
paths_to_add = [paths_to_add;...
    paths.task;...
    paths.stim;...
    paths.code_exp_scripts;...
    ];

 addpath(paths_to_add{:});

 if exist('bml_defaults.m','file')
     bml_defaults() % set bml path
 end


% % % end%% if more details are provided, output relevant paths

if exist('op','var')
    if isfield(op,'sub') % if sub specified
        paths.src_sub = [paths.data, filesep,'sourcedata', filesep, 'sub-',op.sub]; 
        paths.der_sub = [paths.data, filesep, 'derivatives', filesep, 'sub-',op.sub]; 
        paths.annot = [paths.der_sub, filesep, 'annot']; 
        paths.runs_table = [paths.annot, filesep, 'sub-',op.sub, '_runs.tsv'];
        % paths.landmarks_file = [paths.annot filesep, ]; 
        paths.trial_audio = [paths.der_sub, filesep, 'trial-audio']; 

        if isfield(op,'ses') % if session specified
            paths.src_ses = [paths.src_sub, filesep,'ses-',op.ses]; 
            paths.src_task = [paths.src_ses, filesep, 'task'];
            paths.src_audio = [paths.src_ses, filesep, 'audio'];
             
                if isfield(op,'run') % if run specified
                    if ischar(op.run)
                        op.runstring = op.run;
                    elseif isnumeric(op.run)
                        op.runstring = sprintf('%02.0f', op.run); % expect run string as 2 digits; zero pad
                    else
                        error('unrecognized run label format - should be string or number')
                    end

                    %%%% the following string gets used in a variety of files associated with this run
                    paths.filestr = ['sub-',op.sub, '_ses-',op.ses, '_task-daf_run-',num2str(op.runstring), '_']; 
                    
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