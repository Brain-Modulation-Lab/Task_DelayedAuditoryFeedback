function [total_blocks]=get_randomized_stim_trials(stim_cond_add,sentences_number,number_of_blocks )

Stimcond=readtable(stim_cond_add);
%%
arr_stimcond=table2array(Stimcond);
stim_cond_number= 3;
gcd_sentence_stim=gcd(sentences_number,stim_cond_number);
last_sent_id_prev_block=-1;
bb=0;% block counter
while bb < number_of_blocks
    bb=bb+1;
    %% create a block of data
    % random selection of sentences
    for repeat_sent= 1:stim_cond_number/gcd_sentence_stim
        if repeat_sent == 1
            sampled_indexes_sent=transpose( datasample(1:sentences_number, sentences_number,'Replace',false));
            % make sure two consecutive block sentences are not the same
            while  sampled_indexes_sent(1)==last_sent_id_prev_block
                sampled_indexes_sent= transpose(datasample(1:sentences_number, sentences_number,'Replace',false));
            end
        else
            sampled_indexes_sent_temp= transpose(datasample(1:sentences_number, sentences_number,'Replace',false));
    
            % make sure two consecutive sentences are not the same
            while  sampled_indexes_sent_temp(1)==sampled_indexes_sent(end)
                sampled_indexes_sent_temp= transpose(datasample(1:sentences_number, sentences_number,'Replace',false));
            end
            sampled_indexes_sent= cat(1,sampled_indexes_sent, sampled_indexes_sent_temp);
    
        end
    end
    
    % random selection of stimuation
    for repeat_stim= 1:sentences_number/gcd_sentence_stim
        if repeat_stim == 1
            sampled_indexes_stim= datasample(Stimcond.indx, length(Stimcond.indx),'Replace',false);
        else
            sampled_indexes_stim_temp= datasample(Stimcond.indx, length(Stimcond.indx),'Replace',false);
    
            % make sure two consecutive stims are not the same
            while  sampled_indexes_stim_temp(1)==sampled_indexes_stim(end)
                sampled_indexes_stim_temp= datasample(Stimcond.indx, length(Stimcond.indx),'Replace',false);
            end
            sampled_indexes_stim= cat(1,sampled_indexes_stim, sampled_indexes_stim_temp);
    
        end
    end
    
    % put together the block
    stims=arr_stimcond(sampled_indexes_stim,1:end);
    stims(:,1)=sampled_indexes_sent;
    last_sent_id_prev_block=sampled_indexes_sent(end);
    block_table=array2table(stims,'VariableNames', ...
        {'sent_id','stim_epoch', 'stim_location','stim_frequency' });
    if bb==1
        total_blocks=block_table;
    else
        total_blocks = vertcat(total_blocks, block_table);
    end
end

