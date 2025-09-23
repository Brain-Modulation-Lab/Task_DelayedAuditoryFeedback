function log_metadata(cfg, dbEventFile)

%% Embedding de-indetified metadata into pairs of label and value triggers
fprintf('\nDictionary used for metadata embedding:\nlabel [labelcode] options\n\n')
labelcodedict = label_value();
labelcodedict(:,3) = cellfun(@(x) strjoin([{' '},x]),labelcodedict(:,3),'UniformOutput',false);
labelcodedict = labelcodedict';
fprintf('%s [%i] %s\n', labelcodedict{:}) 
fprintf('\n\n');

log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); 

% embedding run time-of-day info into event codes
[hour,minute,second] = hms(datetime('now'));

[labelcode,value]=label_value('version');
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], labelcode, 'Label',0); WaitSecs(0.001); %dict version
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], value, 'Value',0); WaitSecs(0.001); %dict version
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); WaitSecs(0.001);


[labelcode,value]=label_value('hour',hour);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], labelcode, 'Label',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], value, 'Value',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); WaitSecs(0.001);


[labelcode,value]=label_value('minute',minute);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], labelcode, 'Label',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], value, 'Value',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); WaitSecs(0.001);

[labelcode,value]= label_value('second',round(second));
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], labelcode, 'Label',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], value, 'Value',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); WaitSecs(0.001);

% embedding subject id 
subjectCohort = regexp(cfg.SUBJECT,'[a-zA-Z]+','match');
subjectCohort = subjectCohort{1};
subjectSerieNumber = regexp(cfg.SUBJECT,'[0-9]+','match');
subjectSerieNumber = str2double(subjectSerieNumber{1});
subjectNumber = mod(subjectSerieNumber,100);
subjectSerie = round((subjectSerieNumber-subjectNumber)/100);

[labelcode,value]= label_value('subject_cohort',subjectCohort);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], labelcode, 'Label',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], value, 'Value',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); WaitSecs(0.001);

[labelcode,value]= label_value('subject_serie',subjectSerie);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], labelcode, 'Label',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], value, 'Value',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); WaitSecs(0.001);

[labelcode,value]= label_value('subject_number',subjectNumber);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], labelcode, 'Label',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], value, 'Value',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); WaitSecs(0.001);

% embedding session task and run info
[labelcode,value]= label_value('session',cfg.SESSION_LABEL);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], labelcode, 'Label',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], value, 'Value',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); WaitSecs(0.001);

[labelcode,value]= label_value('task',cfg.TASK);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], labelcode, 'Label',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], value, 'Value',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); WaitSecs(0.001);

[labelcode,value]= label_value('task_version',cfg.TASK_VERSION);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], labelcode, 'Label',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], value, 'Value',0); WaitSecs(0.001);
log_event(dbEventFile, cfg.DIGOUT, [], [], [], [], [], 0, 'Zero',0); WaitSecs(0.001);


