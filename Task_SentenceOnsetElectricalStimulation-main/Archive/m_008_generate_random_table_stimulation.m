close all
clear all
clc
%% read the stimualtion table

number_of_blocks=4;
total_blocks = get_randomized_stim_trials("Stimcond.csv",number_of_blocks );
