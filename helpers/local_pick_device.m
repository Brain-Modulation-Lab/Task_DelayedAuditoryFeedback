function idx = local_pick_device(mask, devNames, wantName, what, outCh, inCh, pickOutputs)
    cand = find(mask);
    if isempty(cand)
        error('%s not found. No candidates on this API.', what);
    end
    % First try exact (case-insensitive) match on name if provided
    if strlength(wantName) > 0
        exact = cand(strcmpi(devNames(cand), wantName));
        if numel(exact) == 1
            idx = exact; return;
        elseif numel(exact) > 1
            cand = exact; % still multiple -> keep filtering
        else
            % fallback to substring match
            sub = cand(contains(devNames(cand), wantName, 'IgnoreCase', true));
            if numel(sub) == 1, idx = sub; return; end
            if ~isempty(sub), cand = sub; end
        end
    end
    % If still multiple, pick the one with most channels of the right type
    ch  = pickOutputs .* outCh(cand) + (~pickOutputs) .* inCh(cand);
    [~,best] = max(ch);
    idx = cand(best);
end