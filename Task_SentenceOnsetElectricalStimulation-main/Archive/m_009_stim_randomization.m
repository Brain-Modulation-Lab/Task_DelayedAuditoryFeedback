close all
clear all
clc
%%
sentences_number=10;
stim_epoch=3;
stim_location=2;
stim_frequency=2;
number_of_blocks=1;
total_blocks=get_randomized_stims(sentences_number, ...
    stim_epoch, stim_location, stim_frequency, number_of_blocks);