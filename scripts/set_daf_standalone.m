% simple script for changing DAF delay on Eventide H90
%%%% assumes that you have already created a preset where:
% parameter = Delay A
% CC # = 1
% CTl Source = MIDI CC
% Control Range = 0-500ms
% 
% ..... you can double check these settings on Eventide:
%     PARAMETERS [press unilt Delay A appears]
%     press and hold black knob under Delay A ... we're not using Delay B
%     scroll through parameters with SELECT to check them
%
%
% AM 2026

% clear

% delay_ms = 500; % may want to test out multiple values to check mapping
eventide_dev_name = 'H90 Pedal';
chan = 1; % this should already be set on the Eventide
cc_num = 1; % this should already be set on the Eventide

mididevinfo % commandline display

midi_info = mididevinfo;

h90_idx = find(contains({midi_info.output.Name}, eventide_dev_name));

h90port = mididevice('Output', midi_info.output(h90_idx).ID);

% cc_val = compute_midi_delay_val(delay_ms); % estimate cc_val for desired delay

midisend(h90port, 'ControlChange', chan, cc_num, cc_val);