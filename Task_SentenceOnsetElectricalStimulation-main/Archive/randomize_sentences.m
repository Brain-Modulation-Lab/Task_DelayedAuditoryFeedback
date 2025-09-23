function dbTrials = randomize_sentences(cfg)
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

%pseudo randomization, ensuring balanced conditions every n_rep_balance_block repetitions
k =  cfg.n_rep_balance_block;
floor_nrep_over_k = floor(cfg.n_repetitions/k); 
block_noise = [];
for b=1:(floor_nrep_over_k-1)
    if b==1 && cfg.block1_silent %forcing 1st block to be silent
        tmp_block_noise = repmat(1:cfg.n_noise_conditions,k);
        block_noise =  [0, tmp_block_noise(randperm(length(tmp_block_noise)))];
    else
        tmp_block_noise = repmat(0:cfg.n_noise_conditions,k);
        block_noise = [block_noise, tmp_block_noise(randperm(length(tmp_block_noise)))];
    end
end
tmp_block_noise = repmat(0:cfg.n_noise_conditions,[1,cfg.n_repetitions - k.*(floor_nrep_over_k-1)]);
block_noise = [block_noise, tmp_block_noise(randperm(length(tmp_block_noise)))];

dbTrials = table();
n_sentences = height(cfg.db_sentences);
last_sentence_id = 0;
for i=1:length(block_noise)
    tmp = cfg.db_sentences;
    tmp = tmp(randperm(height(tmp)),:);
    tmp.noise_type(:) = block_noise(i);
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
    
    if mod(i-1,cfg.n_rep_balance_block .* (cfg.n_noise_conditions + 1)) == 0
        tmp.pause_point(1)=1;
    end
    
    dbTrials = [dbTrials; tmp];
end

% if ~cfg.block
%     dbTrials = dbTrials(randperm(height(dbTrials)),:);
% end

dbTrials.trial_id = (1:height(dbTrials))';

dbTrials = dbTrials(:,{'trial_id','block_id','sentence_id','noise_type','sentence','file_audio','file_text','pause_point'});

