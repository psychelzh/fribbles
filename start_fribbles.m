function [recordings, status, exception] = start_fribbles(args)
% START_FRIBBLES starts the main experiment

arguments
    % set experiment part, i.e., practice or testing
    args.Part {mustBeMember(args.Part, ["prac", "test"])} = "prac"
    args.Phase {mustBeMember(args.Phase, ["encoding", "retrieval"])} = "encoding"
end

% ---- prepare sequences ----
args_cell = namedargs2cell(args);
config = init_config(args_cell{:});

% ---- set default error related outputs ----
status = 0;
exception = [];

% ---- set experiment timing parameters (predefined here, all in secs) ----
% fixation duration
time_fixation_secs = 1;
% stimuli duration
time_stimuli_secs_min = 0.5;
time_stimuli_secs_max = 3;
% feedback duration
time_feedback_secs = 2.5;

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
    % disable character input and hide mouse cursor
    ListenChar(2);
    HideCursor;
    % set blending function
    Screen('BlendFunction', window_ptr, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    % set default font name and size
    Screen('TextFont', window_ptr, 'SimHei');
    Screen('TextSize', window_ptr, 64);

    % ---- timing information ----
    % get inter flip interval
    ifi = Screen('GetFlipInterval', window_ptr);

    % ---- keyboard settings ----
    keys.start = KbName('space');
    keys.exit = KbName('Escape');
    keys.left = KbName('f');
    keys.right = KbName('j');

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
    [xcenter, ycenter] = RectCenter(window_rect);
    xpixels = RectWidth(window_rect);
    distance = 0.3 * xpixels;
    stim_width = 0.15 * xpixels;

    % ---- present stimuli ----
    % display welcome screen and wait for a press of 's' to start
    instr = strjoin(readlines( ...
        fullfile('config', strcat('instr_', args.Phase, '.txt')), ...
        'EmptyLineRule', 'skip'), '\n');
    DrawFormattedText(window_ptr, double(char(instr)), 'center', 'center');
    Screen('Flip', window_ptr);
    % the flag to determine if the experiment should exit early
    early_exit = false;
    % here we should detect for a key press and release
    while true
        [~, resp_code] = KbStrokeWait(-1);
        if resp_code(keys.start)
            break
        elseif resp_code(keys.exit)
            early_exit = true;
            break
        end
    end
    for i_trial = 1:height(config)
        if early_exit, break, end
        % trial part 1: fixation
        num_frames = round(time_fixation_secs / ifi);
        vbl = Screen('Flip', window_ptr);
        for i = 1:num_frames
            DrawFormattedText(window_ptr, '+', 'center', 'center', [0, 0, 0]);
            Screen('DrawingFinished', window_ptr);
            [~, ~, resp_code] = KbCheck(-1);
            if resp_code(keys.exit)
                early_exit = true;
                break
            end
            vbl = Screen('Flip', window_ptr, vbl + 0.5 * ifi);
        end
        if early_exit, break, end
        % trial part 2: stimuli
        cur_trial = config(i_trial, :);
        num_frames = round(time_stimuli_secs_max / ifi);
        vbl = Screen('Flip', window_ptr);
        if args.Phase == "encoding"
            stim_onset_timestamp = vbl;
        end
        for i = 1:num_frames
            draw_stimuli(cur_trial, 'hide_crown')
            if args.Part == "prac"
                switch args.Phase
                    case "encoding"
                        DrawFormattedText(window_ptr, double('谁跑得更快?'), ...
                            'center', ycenter + stim_width);
                    case "retrieval"
                        DrawFormattedText(window_ptr, double('此时仔细观察，不要操作'), ...
                            'center', ycenter + stim_width);
                end
            end
            Screen('DrawingFinished', window_ptr);
            [resp_made, resp_timestamp, resp_code] = KbCheck(-1);
            if resp_code(keys.exit)
                early_exit = true;
                break
            end
            if args.Phase == "encoding"
                if resp_made && i * ifi >= time_stimuli_secs_min
                    break
                end
            end
            vbl = Screen('Flip', window_ptr, vbl + 0.5 * ifi);
        end
        if early_exit, break, end
        if args.Phase == "encoding"
            [resp, resp_raw, resp_time] = analyze_response();
        end
        % trial part 3: feedback
        num_frames = round(time_feedback_secs / ifi);
        vbl = Screen('Flip', window_ptr);
        if args.Phase == "retrieval"
            stim_onset_timestamp = vbl;
        end
        for i = 1:num_frames
            draw_stimuli(cur_trial, 'show_crown')
            if args.Part == "prac"
                switch args.Phase
                    case "encoding"
                        DrawFormattedText(window_ptr, double('顶上有皇冠的表示跑得更快'), ...
                            'center', ycenter + stim_width);
                    case "retrieval"
                        DrawFormattedText(window_ptr, double('请判断皇冠是否佩戴正确？正确按f，错误按j'), ...
                            'center', ycenter + stim_width);
                end
            end
            Screen('DrawingFinished', window_ptr);
            [resp_made, resp_timestamp, resp_code] = KbCheck(-1);
            if resp_code(keys.exit)
                early_exit = true;
                break
            end
            if args.Phase == "retrieval"
                if resp_made
                    break
                end
            end
            vbl = Screen('Flip', window_ptr, vbl + 0.5 * ifi);
        end
        if early_exit, break, end
        if args.Phase == "retrieval"
            [resp, resp_raw, resp_time] = analyze_response();
        end
        % record user's response
        recordings.resp(i_trial) = resp;
        recordings.resp_raw(i_trial) = resp_raw;
        recordings.acc(i_trial) = resp == cur_trial.cresp;
        recordings.rt(i_trial) = resp_time;
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

    function draw_stimuli(config, feedback)
        draw_fribble(stim_txtrs{config.stim_id_left}, stim_sizes{config.stim_id_left}, ...
            'left', feedback == "show_crown" && config.crown_side == "Left")
        draw_fribble(stim_txtrs{config.stim_id_right}, stim_sizes{config.stim_id_right}, ...
            'right', feedback == "show_crown" && config.crown_side == "Right")
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
            Screen('DrawTexture', window_ptr, feedback_texture, [], feedback_rect)
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
            if ~resp_code(keys.left) && ~resp_code(keys.right)
                resp = "Neither";
            elseif resp_code(keys.left) && resp_code(keys.right)
                resp = "Both";
            elseif resp_code(keys.left)
                resp = "Left";
            else
                resp = "Right";
            end
        end
    end
end
