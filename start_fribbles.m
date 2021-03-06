function [recordings, status, exception] = start_fribbles(args)
% START_FRIBBLES starts the main experiment

arguments
    % set experiment part, i.e., practice or testing
    args.Part {mustBeMember(args.Part, ["prac", "test"])} = "prac"
    args.Treat {mustBeMember(args.Treat, ["exp", "ctrl"])} = "exp"
    args.Phase {mustBeMember(args.Phase, ["encoding", "retrieval"])} = "encoding"
    args.SendTrigger {mustBeNumericOrLogical}
end
part = args.Part;
treat = args.Treat;
phase = args.Phase;
if ismember('SendTrigger', fieldnames(args))
    send_trigger = args.SendTrigger;
else
    send_trigger = part == "test";
end

% --- prepare for trigger ---
if send_trigger
    ioObj = io64;
    io64(ioObj);
    address = hex2dec('C100');
end

% ---- prepare sequences ----
config = init_config();

% ---- set default error related outputs ----
status = 0;
exception = [];

% ---- set experiment timing parameters (predefined here, all in secs) ----
% fixation duration
time_fixation_secs = 1;
% random blank interval range
time_blank_interval = [0.2, 0.4];
% stimuli duration
time_stimuli_secs_min = 0.5;
if treat == "exp"
    time_stimuli_secs_max = 3;
else
    time_stimuli_secs_max = 2.5;
end
% post-stimuli duration
time_poststim_secs = 2.5;
% feedback duration
time_feedback_secs = 0.5;

% ---- prepare valid keys ----
if treat == "exp" && phase == "encoding"
    keys_valid = {'left', 'right'};
elseif treat == "exp" && phase == "retrieval"
    keys_valid = {'correct', 'incorrect'};
else
    keys_valid = {'left', 'right', 'control'};
end

% ----prepare data recording table ----
recordings = config;
recordings.resp = strings(height(config), 1);
recordings.resp_raw = strings(height(config), 1);
recordings.acc = nan(height(config), 1);
recordings.rt = nan(height(config), 1);

% ---- configure screen and window ----
% setup default level of 2
PsychDefaultSetup(2);
% screen selection
screen_to_display = max(Screen('Screens'));
% set the start up screen to black
old_visdb = Screen('Preference', 'VisualDebugLevel', 1);
% do not skip synchronization test to make sure timing is accurate
old_sync = Screen('Preference', 'SkipSyncTests', 0);
% set priority to the top
old_pri = Priority(MaxPriority(screen_to_display));

try
    % ---- open window ----
    % open a window and set its background color as gray
    [window_ptr, window_rect] = PsychImaging('OpenWindow', screen_to_display, WhiteIndex(screen_to_display));
    [xcenter, ycenter] = RectCenter(window_rect);
    xpixels = RectWidth(window_rect);
    % disable character input and hide mouse cursor
    ListenChar(2);
    HideCursor;
    % set blending function
    Screen('BlendFunction', window_ptr, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    % set default font name and size
    Screen('TextFont', window_ptr, 'SimHei');
    Screen('TextSize', window_ptr, floor(xpixels * 0.03));

    % ---- timing information ----
    % get inter flip interval
    ifi = Screen('GetFlipInterval', window_ptr);

    % ---- keyboard settings ----
    keys = containers.Map('KeyType', 'char', 'ValueType', 'double');
    keys('start') = KbName('space');
    keys('exit') = KbName('Escape');
    keys('left') = KbName('f');
    keys('right') = KbName('j');
    keys('correct') = KbName('c');
    keys('incorrect') = KbName('n');
    keys('control') = KbName('g');

    % ---- prepare stimuli ----
    files_stim = dir(fullfile('stimuli', '*.png'));
    n_stims = length(files_stim);
    stim_txtrs = cell(size(files_stim));
    stim_sizes = cell(size(files_stim));
    for i_file = 1:n_stims
        [cur_stim, ~, cur_alpha] = imread(fullfile('stimuli', ...
            files_stim(i_file).name));
        cur_stim(:, :, 4) = cur_alpha;
        stim_txtrs{i_file} = Screen('MakeTexture', window_ptr, cur_stim);
        stim_sizes{i_file} = size(cur_stim);
    end
    img_crown = imread(fullfile('config', 'crown.jpg'));
    feedback_texture = Screen('MakeTexture', window_ptr, img_crown);
    size_crown = size(img_crown);
    distance = 0.3 * xpixels;
    stim_width = 0.15 * xpixels;

    % ---- present stimuli ----
    % display welcome screen and wait for a press of 's' to start
    instr = strjoin(readlines( ...
        fullfile('config', sprintf('instr_%s_%s.txt', treat, phase)), ...
        'EmptyLineRule', 'skip'), '\n');
    DrawFormattedText(window_ptr, double(char(instr)), 'center', 'center');
    Screen('Flip', window_ptr);
    % the flag to determine if the experiment should exit early
    early_exit = false;
    % here we should detect for a key press and release
    while true
        [~, resp_code] = KbStrokeWait(-1);
        if resp_code(keys('start'))
            break
        elseif resp_code(keys('exit'))
            early_exit = true;
            break
        end
    end
    last_block_id = 0;
    for i_trial = 1:height(config)
        if early_exit, break, end
        cur_trial = config(i_trial, :);
        if cur_trial.block_id ~= last_block_id
            if send_trigger
                % send trigger: each new block start
                io64(ioObj, address, 30 + cur_trial.block_id);
            end
            last_block_id = cur_trial.block_id;
        end
        % trial part 1: fixation
        num_frames = round(time_fixation_secs / ifi);
        vbl = Screen('Flip', window_ptr);
        for i = 1:num_frames
            DrawFormattedText(window_ptr, '+', 'center', 'center', [0, 0, 0]);
            Screen('DrawingFinished', window_ptr);
            [~, ~, resp_code] = KbCheck(-1);
            if resp_code(keys('exit'))
                early_exit = true;
                break
            end
            vbl = Screen('Flip', window_ptr, vbl + 0.5 * ifi);
        end
        if early_exit, break, end
        % random blank interval
        time_rand_secs = time_blank_interval(1) + ...
            (time_blank_interval(2) - time_blank_interval(1)) * rand(1, 1);
        num_frames = round(time_rand_secs / ifi);
        vbl = Screen('Flip', window_ptr);
        for i = 1:num_frames
            [~, ~, resp_code] = KbCheck(-1);
            if resp_code(keys('exit'))
                early_exit = true;
                break
            end
            vbl = Screen('Flip', window_ptr, vbl + 0.5 * ifi);
        end
        if early_exit, break, end
        % trial part 2: stimuli
        num_frames = round(time_stimuli_secs_max / ifi);
        vbl = Screen('Flip', window_ptr);
        if treat == "exp" && phase == "encoding"
            stim_onset_timestamp = vbl;
            if send_trigger
                % send trigger: stimuli onset
                io64(ioObj, address, 11);
            end
        elseif treat == "exp" && phase == "retrieval"
            if send_trigger
                % send trigger: stimuli onset
                io64(ioObj, address, 21);
            end
        end
        for i = 1:num_frames
            draw_stimuli(cur_trial, 'hide_crown')
            if part == "prac"
                if treat == "exp" && phase == "encoding"
                    fb_text = '?????????????????????????F????????????J';
                else
                    fb_text = '?????????????????????????????????';
                end
                DrawFormattedText(window_ptr, double(fb_text), ...
                    'center', ycenter + stim_width);
            end
            Screen('DrawingFinished', window_ptr);
            [resp_made, resp_timestamp, resp_code] = KbCheck(-1);
            if resp_code(keys('exit'))
                early_exit = true;
                break
            end
            if treat == "exp" && phase == "encoding"
                if resp_made && i * ifi >= time_stimuli_secs_min
                    break
                end
            end
            vbl = Screen('Flip', window_ptr, vbl + 0.5 * ifi);
        end
        if early_exit, break, end
        if treat == "exp" && phase == "encoding"
            [resp, resp_raw, resp_time] = analyze_response();
            if send_trigger
                if resp == ""
                    code = 3;
                else
                    code = (resp ~= cur_trial.cresp) + 1;
                end
                % send trigger: stimuli offset or response made (encoding)
                io64(ioObj, address, 12);
                % send trigger: response code
                io64(ioObj, address, code);
            end
        end
        % random blank interval
        time_rand_secs = time_blank_interval(1) + ...
            (time_blank_interval(2) - time_blank_interval(1)) * rand(1, 1);
        num_frames = round(time_rand_secs / ifi);
        vbl = Screen('Flip', window_ptr);
        for i = 1:num_frames
            [~, ~, resp_code] = KbCheck(-1);
            if resp_code(keys('exit'))
                early_exit = true;
                break
            end
            vbl = Screen('Flip', window_ptr, vbl + 0.5 * ifi);
        end
        if early_exit, break, end
        % trial part 3: post stimuli phase
        num_frames = round(time_poststim_secs / ifi);
        vbl = Screen('Flip', window_ptr);
        if treat == "exp" && phase == "encoding"
            if send_trigger
                % send trigger: crown onset
                io64(ioObj, address, 13);
            end
        else
            if treat == "exp" && phase == "retrieval"
                if send_trigger
                    if cur_trial.cresp == "correct"
                        code = 22;
                    else
                        code = 23;
                    end
                    % send trigger: crown onset with type
                    io64(ioObj, address, code);
                end
            end
            stim_onset_timestamp = vbl;
        end
        for i = 1:num_frames
            if treat == "exp"
                draw_stimuli(cur_trial, 'show_crown')
            end
            if part == "prac"
                switch treat
                    case "exp"
                        switch phase
                            case "encoding"
                                fb_text = '????????????????????????????????????';
                            case "retrieval"
                                fb_text = '?????????????????????????????????????????????C????????????N';
                        end
                        DrawFormattedText(window_ptr, double(fb_text), ...
                            'center', ycenter + stim_width);
                    case "ctrl"
                        switch phase
                            case "encoding"
                                fb_text = '?????????\n?????????????????????F???????????????J???????????????G';
                            case "retrieval"
                                fb_text = '?????????\n?????????F???????????????J???????????????G';
                        end
                        DrawFormattedText(window_ptr, double(fb_text), ...
                            'center', 'center');
                end
            end
            Screen('DrawingFinished', window_ptr);
            [resp_made, resp_timestamp, resp_code] = KbCheck(-1);
            if resp_code(keys('exit'))
                early_exit = true;
                break
            end
            if ~(treat == "exp" && phase == "encoding")
                if resp_made
                    break
                end
            end
            vbl = Screen('Flip', window_ptr, vbl + 0.5 * ifi);
        end
        if early_exit, break, end
        if treat == "exp" && phase == "encoding"
            if send_trigger
                % send trigger: crown offset
                io64(ioObj, address, 14);
            end
        else
            [resp, resp_raw, resp_time] = analyze_response();
            if treat == "exp" && phase == "retrieval"
                if send_trigger
                    if resp == ""
                        code = 3;
                    else
                        code = (resp ~= cur_trial.cresp) + 1;
                    end
                    % send trigger: stimuli offset or response made (retrieval)
                    io64(ioObj, address, 24);
                    % send trigger: response code
                    io64(ioObj, address, code);
                end
            end
        end
        % record user's response
        recordings.resp(i_trial) = resp;
        recordings.resp_raw(i_trial) = resp_raw;
        recordings.acc(i_trial) = resp == cur_trial.cresp;
        recordings.rt(i_trial) = resp_time;
        % trial part 4: feedback phase for practice only
        if part == "prac"
            num_frames = round(time_feedback_secs / ifi);
            vbl = Screen('Flip', window_ptr);
            for i = 1:num_frames
                if resp ~= ""
                    if resp == cur_trial.cresp
                        fb_text = '?????????????????????';
                    else
                        fb_text = '???????????????';
                    end
                else
                    fb_text = '???????????????????????????';
                end
                DrawFormattedText(window_ptr, double(fb_text), ...
                    'center', 'center', [1, 0, 0]);
                Screen('DrawingFinished', window_ptr);
                [resp_made, resp_timestamp, resp_code] = KbCheck(-1);
                if resp_code(keys('exit'))
                    early_exit = true;
                    break
                end
                vbl = Screen('Flip', window_ptr, vbl + 0.5 * ifi);
            end
            if early_exit, break, end
        end
    end
catch exception
    status = 1;
end

% clear and reset
sca;
ListenChar;
ShowCursor;
Screen('Preference', 'VisualDebugLevel', old_visdb);
Screen('Preference', 'SkipSyncTests', old_sync);
Priority(old_pri);

    function config = init_config()
        switch part
            case "prac"
                if treat == "exp"
                    % set different random seed when practice
                    rng('Shuffle')
                else
                    % use the same random seed for control
                    rng(sum(char(treat)))
                end
                num_blocks = 1;
                num_trials = 6;
            case "test"
                % same random seed for entire control treatment
                if treat == "exp"
                    rng(sum(char(treat + phase)))
                else
                    rng(sum(char(treat)))
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
        switch treat
            case "exp"
                if phase == "encoding"
                    stims.crown_side = sides((stims.speed_left < stims.speed_right) + 1);
                    stims.cresp = stims.win_side;
                else
                    stims.crown_side = datasample(sides, height(stims));
                    resps = ["incorrect", "correct"]';
                    stims.cresp = resps((stims.win_side == stims.crown_side) + 1);
                end
            case "ctrl"
                if part == "prac"
                    num_ctrl = 2;
                else
                    num_ctrl = 24;
                end
                % prepare encoding part
                is_ctrl_enc = false(num_trials, 1);
                row_ctrl_enc = datasample(1:num_trials, num_ctrl, 'Replace', false);
                is_ctrl_enc(row_ctrl_enc) = true;
                stims.is_ctrl_enc = is_ctrl_enc;
                texts = ["??????", "??????"]';
                stims.text_tip = texts(xor(stims.win_side == "left", is_ctrl_enc) + 1);
                % prepare retrieval part
                if phase == "retrieval"
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


    function draw_stimuli(config, feedback)
        if treat == "exp"
            crown_side = config.crown_side;
        else
            crown_side = "";
        end
        draw_fribble(stim_txtrs{config.stim_id_left}, stim_sizes{config.stim_id_left}, ...
            'left', feedback == "show_crown" && crown_side == "left")
        draw_fribble(stim_txtrs{config.stim_id_right}, stim_sizes{config.stim_id_right}, ...
            'right', feedback == "show_crown" && crown_side == "right")
        if treat == "ctrl"
            DrawFormattedText(window_ptr, double(char(config.text_tip)), 'center', 'center');
            if (phase == "encoding" && config.is_ctrl_enc) || ...
                    (phase == "retrieval" && config.is_ctrl_ret)
                Screen('FillPoly', window_ptr, [0, 0, 1], ...
                    [xcenter - stim_width / 4, ycenter - stim_width / 2; ...
                    xcenter + stim_width / 4, ycenter - stim_width / 2; ...
                    xcenter, ycenter - (1 / 2 + sqrt(3) / 4) * stim_width]);
            end
        end
    end

    function draw_fribble(texture, texture_size, side, feedback)
        switch side
            case 'left'
                stim_center_x = xcenter - distance / 2;
            case 'right'
                stim_center_x = xcenter + distance / 2;
        end
        stim_scale = stim_width / texture_size(2);
        dest_rect = CenterRectOnPoint( ...
            [0, 0, floor(texture_size(2:-1:1) * stim_scale)], ...
            stim_center_x, ycenter);
        Screen('DrawTexture', window_ptr, texture, [], dest_rect)
        if feedback
            feedback_scale = stim_width / texture_size(2);
            feedback_center_y = ycenter - stim_width;
            feedback_rect = CenterRectOnPoint( ...
                [0, 0, floor(size_crown(2:-1:1) * feedback_scale)], ...
                stim_center_x, feedback_center_y);
            Screen('DrawTexture', window_ptr, feedback_texture, [], feedback_rect);
        end
    end

    function [resp, resp_raw, resp_time] = analyze_response()
        if ~resp_made
            resp = "";
            resp_raw = "";
            resp_time = 0;
        else
            resp_time = resp_timestamp - stim_onset_timestamp;
            % use "|" as delimiter for the KeyName of "|" is "\\"
            resp_raw = string(strjoin(cellstr(KbName(resp_code)), '|'));
            resp_codes_valid = cellfun(@(x) x, values(keys, keys_valid));
            resp_codes = find(resp_code);
            resp_idx = ismember(resp_codes_valid, resp_codes);
            if sum(resp_idx) == 1 && length(resp_codes) == 1
                resp = string(keys_valid{resp_idx});
            else
                resp = "invalid";
            end
        end
    end
end
