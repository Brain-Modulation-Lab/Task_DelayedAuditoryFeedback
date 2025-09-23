function dbTrials = randomize_sentences_stim(cfg)
% Returns a randomized trial order with noise_type
%
% Use as dbTrials = randomize_cardinal_vowels_sentences(cfg)
%
% cfg.db_sentences - table with columns sentence_id, sentence, file
% cfg.n_noise_conditions - number of noise conditions to be added to silent condition
%                       e.g. n_noise_conditions=2 then two noise
%                       conditions plus the no-noise condition will be created
% cfg.n_repetitions - number of repetitions of each sentence in each noise
%                       condition
% cfg.n_rep_balance_block - number of repetitions of each sentence at which
%                       the experiment should be balanced. For example, if 2, 
%                       n_rep_balance_block=2 and n_noise_conditions=1, the
%                       experiment will be balanced every 4th block. 
% cfg.block - bool, indicating if trials should be blocked by noise condition
% cfg.block1_silent - boolean indicating if block 1 should be forced to
%                     have no noise
%
% returns a table with pseudo-randomized trial order and noise conditions


assert(istable(cfg.db_sentences), 'cfg.db_sentences table required')
assert(all(ismember({'sentence_id','sentence','file_audio','file_text'},cfg.db_sentences.Properties.VariableNames)), 'incorrect variables for table')
cfg.db_sentences = cfg.db_sentences(:,{'sentence_id','sentence','file_audio','file_text'});

%% Stimulation table
total_blocks_stims=get_randomized_stims(height(cfg.db_sentences), ...
    cfg.stim_epoch, cfg.stim_location, cfg.stim_frequency, cfg.n_repetitions);
total_stm_cond_num=cfg.stim_epoch * cfg.stim_location * cfg.stim_frequency;
gcd_n=gcd(total_stm_cond_num,height(cfg.db_sentences));
%pseudo randomization, ensuring balanced conditions every n_rep_balance_block repetitions

dbTrials = table();
n_sentences = height(cfg.db_sentences);
last_sentence_id = 0;
for i=1: cfg.n_repetitions*total_stm_cond_num/gcd_n
    tmp = cfg.db_sentences;
    tmp = tmp(randperm(height(tmp)),:);
    tmp.noise_type(:) =0;
    tmp.block_id(:) = i;
    tmp.pause_point(:) = 0;
	
    %avoiding repeating same sentence 2 times in a row
    if tmp.sentence_id(1) == last_sentence_id
      swap_i = randi(n_sentences-1)+1;
      tmp(n_sentences+1,:)=tmp(1,:);
      tmp(1,:)=tmp(swap_i,:);
      tmp(swap_i,:)=tmp(n_sentences+1,:);
      tmp(n_sentences+1,:)=[];
    end
    last_sentence_id = tmp.sentence_id(n_sentences);
    dbTrials = [dbTrials; tmp];
end

% if ~cfg.block
%     dbTrials = dbTrials(randperm(height(dbTrials)),:);
% end
dbTrials=[dbTrials,total_blocks_stims];
dbTrials.trial_id = (1:height(dbTrials))';

dbTrials = dbTrials(:,{'trial_id','block_id','sentence_id','noise_type', ...
    'sentence','file_audio','file_text','pause_point', 'stim_epoch', ...
    'stim_location','stim_frequency'});

