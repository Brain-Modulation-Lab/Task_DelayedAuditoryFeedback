% switch from labels used in trial table to those we want to put on plots
%%%    events_in is a cell arrray of strings

function events_out = relabel_events_daf(events_in)

events_out = cell(size(events_in)); 

for i_ev = 1:length(events_in)
    switch events_in{i_ev}
        case 't_vis_stim_on'
             events_out{i_ev} = {'visual','on'};
        case 't_vis_stim_off'
             events_out{i_ev} = {'visual','off'};
        case 't_aud_go_on'
             events_out{i_ev} = {'GO','cue'};
        case 't_aud_go_off'
             events_out{i_ev} = {'GO','off'};
        case 't_prod_on'
             events_out{i_ev} = {'speech','on'};
        case 't_prod_off'
             events_out{i_ev} = {'speech','off'};

    end
end
