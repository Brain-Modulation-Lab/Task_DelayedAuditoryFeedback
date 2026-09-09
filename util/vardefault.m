% vardefault(query_var,default_val)
%%%% if query_var exists and is not empty, leave as is; if does not exist or is empty,
%%%% set to default 
% updated 2026 by Andrew Meier - no longer provides output so that it can be used without suppressing output

function vardefault(query_var,default_val)

if ~[ evalin('caller',['exist(''',query_var,''',''var'')'])... % if var exists in caller workspace
    && evalin('caller',['~isempty(',query_var,')']) ] %%% and is not empty

        assignin('caller', query_var, default_val)

end