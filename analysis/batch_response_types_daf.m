% get response types from each dbs-seq subject then compile into a single table

clear
paths = set_paths_daf(); 

% params
subject_list_filename = [paths.task, filesep, 'daf-subs-master.xlsx']; 

freq_bands_to_analyze = {'beta','hg'}; 
% freq_bands_to_analyze = {'beta'}; 
% freq_bands_to_analyze = {'hg'}; 

op.art_crit = 'G'; 
op.denoise_string = '_not_denoised'; %%% comment out??

op.baseline_method = 'subtract_then_divide'; % options: 'divide_then_subtract','subtract'

subnums = [...
    1057  
     ];

% subnums = 1024;




%% set up sub list
subnames = arrayfun(@(x)['DM',num2str(x)],subnums','UniformOutput',0);
subs = readtable(subject_list_filename);
subs = subs(cellfun(@(x)ismember(x,subnames),subs.sub), :); 
nsubs = height(subs);

nbands = length(freq_bands_to_analyze);
for iband = 1:nbands % run full analysis, compile subjects, save results for all signals of interest
    op.resp_signal = freq_bands_to_analyze{iband};
    compiled_responses_filepath = [paths.results, filesep, 'resp_all_subjects_', op.resp_signal]; 

    % run response type analysis on each subject individually
    for isub = 1:nsubs    
        op.sub = subs.sub{isub}
        
        [resp, trials, op] = response_types_daf(op);
        savefile = [paths.results, filesep, op.sub '_responses_' op.resp_signal];
        save(savefile, 'trials','resp','op'); clear resp trials
    end

    
    % combine responses from all subjects into one table
    fprintf(['Compiling response tables (good elcs only) in %s \n'], compiled_responses_filepath);
    resp_all = table; 
    for isub = 1:nsubs
        op.sub = subs.sub{isub};
        load([paths.results, filesep, op.sub, '_responses_', op.resp_signal],'resp','trials','op')
        resp_all = [resp_all; resp(~resp.bad_elc,:)];
        subs.trials{isub} = trials; 
    end

    resp = resp_all; clear resp_all; op = rmfield(op,'sub'); 
    save(compiled_responses_filepath, 'resp','subs','op')
    fprintf(['Saved all-subject response table (good elcs only) in %s \n'], compiled_responses_filepath);

end

cd(paths.results)


