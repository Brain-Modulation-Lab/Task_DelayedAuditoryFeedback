
function cfg = setup_audio_devices(cfg)

aud = struct; 

computername = getenv('COMPUTERNAME'); % might not work on non-windows machines
    computername = deblank(computername); 
auddevs = audiodevinfo; 
    devs_in = {auddevs.input.Name};
    devs_out = {auddevs.output.Name};

    switch computername
        case 'BML-ALIENWARE2'
            cfg.PATH_TASK       = 'D:\Task\Task_DelayedAuditoryFeedback';
            cfg.PATH_SOURCEDATA = 'D:\DBS\sourcedata';
        case {'677-GUE-WL-0010','677-GUE-WL-0012'}  % AM Thinkpad X1 laptops
            cfg.PATH_TASK       = 'C:\docs\code\Task_DelayedAuditoryFeedback'; 
            cfg.PATH_SOURCEDATA = 'C:\DBS\sourcedata';
        case 'AMSMEIER' % AM strix laptop
   
        otherwise 
            error('unknown computer')
    end
% % % end


