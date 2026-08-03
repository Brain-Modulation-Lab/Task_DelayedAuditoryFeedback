%%%% import manual annotations from praaat textgrids into the trial table

op.sub = 'DM1057';
op.ses = 'intraop'; 
op.task = 'daf'; 


%% construct praat tier table

praat_tiers_names = {'speech_epoch', 'sld_repetition', 'sld_prolongation',  'typical_disfluency', 'disfluency_resolution',...
    'slowing', 'distortion', 'error',  'comments', 'unusable_trial', 'difficult_to_score'};

n_tiers = length(praat_tiers_names); 
celcol = cell(n_tiers,1); 
nancol = nan(n_tiers,1); 

praat_tiers = table(praat_tiers_names', celcol,   celcol,               celcol, 'VariableNames', ...
                    {'name',           'class','n_times_min_max','timepoint_names'},...
                    'RowNames',praat_tiers_names'); 

praat_tiers.class{'speech_epoch'} = 'timing';
praat_tiers.n_times_min_max{'speech_epoch'} = [2 2]; 
praat_tiers.timepoint_names{'speech_epoch'} = {'sp_on','sp_off'}; 

praat_tiers.class{'sld_repetition'} = 'timing';
praat_tiers.class{'sld_prolongation'} = 'timing';
praat_tiers.class{'typical_disfluency'} = 'timing';
praat_tiers.class{'disfluency_resolution'} = 'timing';
praat_tiers.class{'slowing'} = 'timing';
praat_tiers.class{'distortion'} = 'timing';
praat_tiers.class{'error'} = 'timing';

praat_tiers.class{'unusable_trial'} = 'logical'; 
praat_tiers.class{'difficult_to_score'} = 'logical'; 


%% load trial table

paths = set_paths_daf(op); 

% load table listing file start times of praat textgrid for each trial
trials_audiofiles = readtable(paths.trials_audiofiles, 'FileType','text', 'Delimiter','tab'); 

% ???? does the trial file in annot have any important info not included in the above trials table? 

%% compile textgrids 