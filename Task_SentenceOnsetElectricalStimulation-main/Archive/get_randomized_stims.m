function [total_blocks]=get_randomized_stims(sentences_number, stim_epoch, stim_location, stim_frequency, number_of_blocks)

x = 1:stim_epoch;
y = 1:stim_location;
z = 1:stim_frequency;
[X,Y,Z] = ndgrid(x,y,z);
arr_stimcond = [X(:) Y(:) Z(:)];
arr_stimcond(:,4)=1:stim_epoch*stim_location*stim_frequency;
Stimcond=array2table(arr_stimcond,'VariableNames', {'stim_epoch', 'stim_location','stim_frequency', 'indx' });
gcd_sentence_stim=gcd(sentences_number,stim_epoch*stim_location*stim_frequency);
bb=0;% block counter
while bb < number_of_blocks
    bb=bb+1;
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

    stims=arr_stimcond(sampled_indexes_stim,1:end);

    block_table=array2table(stims,'VariableNames', ...
        {'stim_epoch', 'stim_location','stim_frequency','trial_stim_type_indx' });
    if bb==1
        total_blocks=block_table;
    else
        total_blocks = vertcat(total_blocks, block_table);
    end
end