% get the approximate ControlChange parameter value to send to Eventide H90
% assume the parameter range is 0-500ms (or else this function can't be used)
% ..... double check this on Eventide:
%     PARAMETERS  [press unilt Delay A appears]
%     press and hold black knob under Delay A ... we're not using Delay B
%     scroll through parameters with SELECT until you see "Control Range"
%     turn the knobs under Start and End to check the min/max values
%
%   The cc_map and delay_map values were determined empirically... the rest of the table is interpolated
%   For ground truth, set a cc_val and look on the Eventide at what the delay is set to
%
% AM 2026

function cc_val = h90_log_interp(target_delay_ms)
    % Empirical Data Points
    cc_map    = [1, 2, 3, 10, 21, 25, 30, 50, 60, 75, 82, 90, 95, 97, 100, 106, 110, 115, 126, 127];
    delay_map_ms = [1, 2, 4, 15, 33, 40, 48, 82, 99, 149, 173, 201, 235, 248, 268, 308, 335, 369, 487, 500];
    
    % Handle the 0/0 case separately (log(0) is undefined)
    if target_delay_ms <= 0
        cc_val = 0; return;
    elseif target_delay_ms >= 500
        cc_val = 127; return;
    end

    % Perform interpolation in Log-Log space for non-linear accuracy
    log_d_map = log10(delay_map_ms);
    log_cc_map = log10(cc_map);
    
    log_target = log10(target_delay_ms);
    
    % Interpolate linearly in the log domain
    log_result = interp1(log_d_map, log_cc_map, log_target, 'linear');
    
    % Convert back to linear CC and round
    cc_val = round(10^(log_result));
end