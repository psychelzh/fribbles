function config = init_config(args)
%INIT_CONFIG generates sequence for current study

arguments
    args.Part {mustBeMember(args.Part, ["prac", "test"])} = "prac"
    args.Treat {mustBeMember(args.Treat, ["exp", "ctrl"])} = "exp"
    args.Phase {mustBeMember(args.Phase, ["encoding", "retrieval"])} = "encoding"
end

switch args.Part
    case "prac"
        % set different random seed when practice
        rng('Shuffle')
        num_blocks = 1;
        num_trials = 6;
    case "test"
        % fix random seed for each phase of task
        rng(sum(char(args.Treat + args.Phase)))
        num_blocks = 5;
        num_trials = 60;
end
config_stim = readtable(fullfile('config', 'stimuli.csv'));
[stim_id_left, stim_id_right] = meshgrid(config_stim.stim_id, config_stim.stim_id);
stim_pairs = table(stim_id_left(:), stim_id_right(:), ...
    'VariableNames', {'stim_id_left', 'stim_id_right'});
[~, row_id_left] = ismember(stim_pairs.stim_id_left, config_stim.stim_id);
[~, row_id_right] = ismember(stim_pairs.stim_id_right, config_stim.stim_id);
stim_pairs.speed_left = config_stim.speed(row_id_left);
stim_pairs.speed_right = config_stim.speed(row_id_right);
stim_pairs = stim_pairs(stim_pairs.speed_left ~= stim_pairs.speed_right, :);
% generate sequence for each block
config = table();
config.block_id = repelem(1:num_blocks, num_trials / num_blocks)';
config.trial_id = (1:num_trials)';
stims = datasample(stim_pairs, num_trials, 'Replace', false);
sides = ["left", "right"]';
stims.win_side = sides((stims.speed_left < stims.speed_right) + 1);
if args.Phase == "encoding"
    stims.crown_side = sides((stims.speed_left < stims.speed_right) + 1);
    stims.cresp = stims.win_side;
else
    stims.crown_side = datasample(sides, height(stims));
    resps = ["incorrect", "correct"]';
    stims.cresp = resps((stims.win_side == stims.crown_side) + 1);
end
config = horzcat(config, stims);
rng('default')
end
