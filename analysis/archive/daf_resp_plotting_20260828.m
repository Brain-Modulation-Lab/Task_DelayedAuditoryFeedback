%%%% plot individual responses to DAF

% load('Y:\DBS\groupanalyses\task-daf\resp_all_subjects_hg.mat')
load('Y:\DBS\groupanalyses\task-daf\resp_all_subjects_beta.mat')


rowlists = {1:25,26:50,51:75,76:100,101:124,125:132};


for ilist = 1:length(rowlists)
    op.rowlist = rowlists{ilist}; 
    plot_sample_timecourses_daf(resp,subs,op)
end