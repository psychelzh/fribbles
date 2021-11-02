function config = init_config(args)
%INIT_CONFIG generates sequence for current study

arguments
    args.Part {mustBeMember(args.Part, ["prac", "test"])} = "prac"
    args.Treat {mustBeMember(args.Treat, ["exp", "ctrl"])} = "exp"
    args.Phase {mustBeMember(args.Phase, ["encoding", "retrieval"])} = "encoding"
end

switch args.Part
    case "prac"
        if args.Treat == "exp"
            % set different random seed when practice
            rng('Shuffle')
        else
            % use the same random seed for control
            rng(sum(char(args.Treat)))
        end
        num_blocks = 1;
        num_trials = 6;
    case "test"
        % same random seed for entire control treatment
        if args.Treat == "exp"
            rng(sum(char(args.Treat + args.Phase)))
        else
            rng(sum(char(args.Treat)))
        end
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
switch args.Treat
    case "exp"
        if args.Phase == "encoding"
            stims.crown_side = sides((stims.speed_left < stims.speed_right) + 1);
            stims.cresp = stims.win_side;
        else
            stims.crown_side = datasample(sides, height(stims));
            resps = ["incorrect", "correct"]';
            stims.cresp = resps((stims.win_side == stims.crown_side) + 1);
        end
    case "ctrl"
        if args.Part == "prac"
            num_ctrl = 2;
        else
            num_ctrl = 24;
        end
        % prepare encoding part
        is_ctrl_enc = false(num_trials, 1);
        row_ctrl_enc = datasample(1:num_trials, num_ctrl, 'Replace', false);
        is_ctrl_enc(row_ctrl_enc) = true;
        stims.is_ctrl_enc = is_ctrl_enc;
        texts = ["慢于", "快于"]';
        stims.text_tip = texts(xor(stims.win_side == "left", is_ctrl_enc) + 1);
        % prepare retrieval part
        if args.Phase == "retrieval"
            is_ctrl_ret = false(num_trials, 1);
            row_ctrl_ret = [datasample( ...
                setdiff(1:num_trials, row_ctrl_enc), num_ctrl / 2, ...
                'Replace', false), ...
                datasample(row_ctrl_enc, num_ctrl / 2, 'Replace', false)];
            is_ctrl_ret(row_ctrl_ret) = true;
            stims.is_ctrl_ret = is_ctrl_ret;
            stims = datasample(stims, num_trials);
            stims.cresp = sides((stims.is_ctrl_enc ~= stims.is_ctrl_ret) + 1);
        else
            stims.cresp = strings(num_trials, 1);
            for i_row = 1:num_trials
                if stims.is_ctrl_enc(i_row)
                    stims.cresp(i_row) = "control";
                else
                    stims.cresp(i_row) = stims.win_side(i_row);
                end
            end
        end
end
config = horzcat(config, stims);
rng('default')
end
