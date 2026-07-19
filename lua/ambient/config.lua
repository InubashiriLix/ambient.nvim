local M = {}

local result          = require("ambient.result")
local progress_styles = require("ambient.progress_styles")

---@enum AmbientConfigError
M.Error = {
    invalid_config = "invalid_config",
    not_ready      = "not_ready",
}

---@type AmbientConfig
local default_config = {
    enable             = true,
    mode               = "interval_random",
    music_dir          = "~/.config/nvim/ambient.music",
    music_dirs         = nil,
    playlists          = nil,
    extensions         = { "mp3", "ogg", "flac", "wav", "m4a", "aac", "opus" },
    recursive_depth    = 4,
    volume             = nil,
    show_notifications = nil,
    volumn_percentage  = 50,
    progress           = {
        enabled   = true,
        layout    = {
            width = 42,
        },
        track     = {
            enabled          = true,
            width            = 18,
            scroll           = false,
            scroll_separator = " ",
        },
        bar       = {
            enabled = true,
            style  = progress_styles.default,
            width  = 10,
            filled = "⠶",
            empty  = "⠄",
            left   = "",
            right  = "",
        },
        time      = {
            enabled = true,
        },
        refresh   = {
            interval_ms = 500,
        },
        component = {
            frame = {
                enabled = false,
                left    = "",
                right   = "",
                padding = " ",
            },
        },
        highlight = {
            default = {
                fg  = "#7CA0F1",
                bg  = "#1e2032",
                gui = "bold",
            },
            states  = {},
        },
    },

    interval = {
        min_ms = 1000 * 60 * 2, -- 2 minutes
        max_ms = 1000 * 60 * 5, -- 5 minutes
    },

    show_notification = {
        disable_all                 = false,
        when_finish_setup           = true,
        when_show_total_music_count = true,
        when_start_playing          = true,
        when_toogle_playing_state   = true,
    },
}

local valid_modes = {
    interval_random             = true,
    interval_sequential         = true,
    without_interval_random     = true,
    without_interval_sequential = true,
    intermittently              = true,
    continuous                  = true,
    continously                 = true,
}

local valid_sort_fields = {
    name        = true,
    duration    = true,
    modify_time = true,
    create_time = true,
    random      = true,
}

local valid_sort_directions = {
    asc  = true,
    desc = true,
}

local deprecated_progress_fields = {
    { "enable",             "enabled" },
    { "style",              "bar.style" },
    { "width",              "layout.width" },
    { "name_width",         "track.width" },
    { "bar_width",          "bar.width" },
    { "show_time",          "time.enabled" },
    { "scroll",             "track.scroll" },
    { "scroll_separator",   "track.scroll_separator" },
    { "update_interval_ms", "refresh.interval_ms" },
    { "border",             "component.frame" },
    { "lualine_separator",  "component.separator" },
    { "color",              "highlight.default" },
    { "colors",             "highlight.states" },
}

local deprecated_progress_component_fields = {
    { "border",            "frame" },
    { "lualine_separator", "separator" },
}

---@class AmbientConfigState
---@field ready boolean
---@field err? AmbientConfigError
---@field err_msg? string
---@field values? AmbientConfig

---@type AmbientConfigState
M.state = {
    ready   = false,
    err     = nil,
    err_msg = nil,
    values  = nil,
}

---@param path string
---@return string
local function normalizePath(path)
    return vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("/$", "")
end

---@param values string[]
---@return string[]
local function normalizeExtensions(values)
    local normalized = {}
    for _, ext in ipairs(values or {}) do
        local item = tostring(ext):lower():gsub("^%.", "")
        if item ~= "" then
            table.insert(normalized, item)
        end
    end
    return normalized
end

---@param value any
---@return boolean
local function isStringArray(value)
    if type(value) ~= "table" then
        return false
    end

    for _, item in ipairs(value) do
        if type(item) ~= "string" then
            return false
        end
    end

    return true
end

---@param value any
---@return boolean
local function isUsablePathString(value)
    return type(value) == "string"
        and value:match("%S") ~= nil
        and value:match("<[^>]+>") == nil
end

---@param value any
---@return boolean
local function isPathArray(value)
    if type(value) ~= "table" then
        return false
    end

    for _, item in ipairs(value) do
        if not isUsablePathString(item) then
            return false
        end
    end

    return true
end

---@param value any
---@return boolean
local function isSingleCellString(value)
    return type(value) == "string" and vim.fn.strdisplaywidth(value) == 1
end

---@param value any
---@return boolean
local function isLualinePadding(value)
    if value == nil then
        return true
    end

    if type(value) == "number" then
        return value >= 0
    end

    if type(value) ~= "table" then
        return false
    end

    local left  = value.left
    local right = value.right
    return (left == nil or (type(left) == "number" and left >= 0))
        and (right == nil or (type(right) == "number" and right >= 0))
end

---@param item table
---@return any
local function getPlaylistPath(item)
    return item.abs_path or item.path or item.dir
end

---@param progress table
local function rejectDeprecatedProgressFields(progress)
    for _, item in ipairs(deprecated_progress_fields) do
        local old_key = item[1]
        local new_key = item[2]
        if progress[old_key] ~= nil then
            error(
                string.format(
                    "progress.%s is no longer supported; use progress.%s",
                    old_key,
                    new_key
                ),
                0
            )
        end
    end

    if type(progress.component) ~= "table" then
        return
    end

    for _, item in ipairs(deprecated_progress_component_fields) do
        local old_key = item[1]
        local new_key = item[2]
        if progress.component[old_key] ~= nil then
            error(
                string.format(
                    "progress.component.%s is no longer supported; use progress.component.%s",
                    old_key,
                    new_key
                ),
                0
            )
        end
    end
end

---@param progress table
local function normalizeProgress(progress)
    rejectDeprecatedProgressFields(progress)

    progress.layout          = progress.layout or {}
    progress.track           = progress.track or {}
    progress.bar             = progress.bar or {}
    progress.time            = progress.time or {}
    progress.refresh         = progress.refresh or {}
    progress.component       = progress.component or {}
    progress.component.frame = progress.component.frame or {}
    progress.highlight       = progress.highlight or {}

    local progress_style = progress_styles.canonical(progress.bar.style)
    if progress_style ~= nil then
        progress.bar.style = progress_style
    end
end

---@param config AmbientConfig
local function normalize(config)
    if config.volume ~= nil then
        config.volumn_percentage = config.volume
    else
        config.volume = config.volumn_percentage
    end

    if type(config.show_notifications) == "boolean" then
        config.show_notification.disable_all = not config.show_notifications
    end

    if config.show_notification.when_toggle_playing_state ~= nil then
        config.show_notification.when_toogle_playing_state = config.show_notification
            .when_toggle_playing_state
    end

    normalizeProgress(config.progress)

    config.extensions = normalizeExtensions(config.extensions)

    local playlist_defaults = {
        ext             = config.extensions,
        recursive_depth = config.recursive_depth,
        sort_field      = (config.mode == "interval_sequential" or config.mode == "without_interval_sequential") and
            "name"
            or "random",
        sort_direction  = "asc",
    }

    local playlists = {}

    if type(config.playlists) == "table" then
        for _, item in ipairs(config.playlists) do
            table.insert(playlists, {
                abs_path        = normalizePath(getPlaylistPath(item)),
                ext             = normalizeExtensions(item.ext or item.extensions or
                    playlist_defaults.ext),
                recursive_depth = item.recursive_depth or playlist_defaults.recursive_depth,
                sort_field      = item.sort_field or item.sort_by or playlist_defaults.sort_field,
                sort_direction  = item.sort_direction or playlist_defaults.sort_direction,
            })
        end
    else
        local dirs = config.music_dirs
        if dirs == nil then
            dirs = { config.music_dir }
        end

        for _, dir in ipairs(dirs) do
            table.insert(playlists, {
                abs_path        = normalizePath(dir),
                ext             = playlist_defaults.ext,
                recursive_depth = playlist_defaults.recursive_depth,
                sort_field      = playlist_defaults.sort_field,
                sort_direction  = playlist_defaults.sort_direction,
            })
        end
    end

    config.playlists = playlists
end

---@param config AmbientConfig
local function validate(config)
    vim.validate({
        enable            = { config.enable, "boolean", "enable must be a boolean" },
        mode              = { config.mode, "string", "mode must be a string" },
        music_dir         = {
            config.music_dir,
            isUsablePathString,
            "music_dir must be a non-empty path, not an angle-bracket placeholder",
        },
        recursive_depth   = {
            config.recursive_depth,
            "number",
            "recursive_depth must be a number",
        },
        volumn_percentage = {
            config.volumn_percentage,
            "number",
            "volumn_percentage must be a number",
        },
        interval          = { config.interval, "table", "interval must be a table" },
        progress          = { config.progress, "table", "progress must be a table" },
        show_notification = {
            config.show_notification,
            "table",
            "show_notification must be a table",
        },
    })

    vim.validate({
        extensions = {
            config.extensions,
            isStringArray,
            "extensions must be a list of strings",
        },
    })

    if config.music_dirs ~= nil then
        vim.validate({
            music_dirs = {
                config.music_dirs,
                isPathArray,
                "music_dirs must be a list of non-empty paths, not angle-bracket placeholders",
            },
        })
    end

    if config.show_notifications ~= nil then
        vim.validate({
            show_notifications = {
                config.show_notifications,
                "boolean",
                "show_notifications must be a boolean",
            },
        })
    end

    vim.validate({
        min_ms = { config.interval.min_ms, "number", "interval.min_ms must be a number" },
        max_ms = { config.interval.max_ms, "number", "interval.max_ms must be a number" },
    })

    vim.validate({
        progress_enabled                = {
            config.progress.enabled,
            "boolean",
            "progress.enabled must be a boolean",
        },
        progress_layout                 = {
            config.progress.layout,
            "table",
            "progress.layout must be a table",
        },
        progress_layout_width           = {
            config.progress.layout.width,
            "number",
            "progress.layout.width must be a number",
        },
        progress_track                  = {
            config.progress.track,
            "table",
            "progress.track must be a table",
        },
        progress_track_enabled          = {
            config.progress.track.enabled,
            "boolean",
            "progress.track.enabled must be a boolean",
        },
        progress_track_width            = {
            config.progress.track.width,
            "number",
            "progress.track.width must be a number",
        },
        progress_track_scroll           = {
            config.progress.track.scroll,
            "boolean",
            "progress.track.scroll must be a boolean",
        },
        progress_track_scroll_separator = {
            config.progress.track.scroll_separator,
            "string",
            "progress.track.scroll_separator must be a string",
        },
        progress_bar                    = {
            config.progress.bar,
            "table",
            "progress.bar must be a table",
        },
        progress_bar_enabled            = {
            config.progress.bar.enabled,
            "boolean",
            "progress.bar.enabled must be a boolean",
        },
        progress_bar_style              = {
            config.progress.bar.style,
            progress_styles.is_valid,
            "progress.bar.style must be one of: " .. progress_styles.describe(),
        },
        progress_bar_body_width         = {
            config.progress.bar.width,
            "number",
            "progress.bar.width must be a number",
        },
        progress_bar_filled             = {
            config.progress.bar.filled,
            isSingleCellString,
            "progress.bar.filled must be a single-cell string",
        },
        progress_bar_empty              = {
            config.progress.bar.empty,
            isSingleCellString,
            "progress.bar.empty must be a single-cell string",
        },
        progress_bar_left               = {
            config.progress.bar.left,
            "string",
            "progress.bar.left must be a string",
        },
        progress_bar_right              = {
            config.progress.bar.right,
            "string",
            "progress.bar.right must be a string",
        },
        progress_time                   = {
            config.progress.time,
            "table",
            "progress.time must be a table",
        },
        progress_time_enabled           = {
            config.progress.time.enabled,
            "boolean",
            "progress.time.enabled must be a boolean",
        },
        progress_refresh                = {
            config.progress.refresh,
            "table",
            "progress.refresh must be a table",
        },
        progress_refresh_interval_ms    = {
            config.progress.refresh.interval_ms,
            "number",
            "progress.refresh.interval_ms must be a number",
        },
        progress_component              = {
            config.progress.component,
            "table",
            "progress.component must be a table",
        },
        progress_frame                  = {
            config.progress.component.frame,
            "table",
            "progress.component.frame must be a table",
        },
        progress_frame_enabled          = {
            config.progress.component.frame.enabled,
            "boolean",
            "progress.component.frame.enabled must be a boolean",
        },
        progress_frame_left             = {
            config.progress.component.frame.left,
            "string",
            "progress.component.frame.left must be a string",
        },
        progress_frame_right            = {
            config.progress.component.frame.right,
            "string",
            "progress.component.frame.right must be a string",
        },
        progress_frame_padding          = {
            config.progress.component.frame.padding,
            "string",
            "progress.component.frame.padding must be a string",
        },
        progress_highlight              = {
            config.progress.highlight,
            "table",
            "progress.highlight must be a table",
        },
        progress_highlight_default      = {
            config.progress.highlight.default,
            "table",
            "progress.highlight.default must be a table",
        },
        progress_color_fg               = {
            config.progress.highlight.default.fg,
            "string",
            "progress.highlight.default.fg must be a string",
        },
        progress_color_bg               = {
            config.progress.highlight.default.bg,
            "string",
            "progress.highlight.default.bg must be a string",
        },
        progress_color_gui              = {
            config.progress.highlight.default.gui,
            "string",
            "progress.highlight.default.gui must be a string",
        },
        progress_colors                 = {
            config.progress.highlight.states,
            "table",
            "progress.highlight.states must be a table",
        },
    })

    if config.progress.component.separator ~= nil then
        vim.validate({
            progress_component_separator       = {
                config.progress.component.separator,
                "table",
                "progress.component.separator must be a table",
            },
            progress_component_separator_left  = {
                config.progress.component.separator.left,
                "string",
                "progress.component.separator.left must be a string",
            },
            progress_component_separator_right = {
                config.progress.component.separator.right,
                "string",
                "progress.component.separator.right must be a string",
            },
        })
    end

    if config.progress.component.padding ~= nil then
        vim.validate({
            progress_component_padding = {
                config.progress.component.padding,
                isLualinePadding,
                "progress.component.padding must be a non-negative number or a table with non-negative left/right numbers",
            },
        })
    end

    for name, value in pairs(config.progress.highlight.states) do
        vim.validate({
            ["progress.highlight.states." .. name] = {
                value,
                "table",
                "progress.highlight.states." .. name .. " must be a table",
            },
        })

        if value.fg ~= nil then
            vim.validate({
                ["progress.highlight.states." .. name .. ".fg"] = {
                    value.fg,
                    "string",
                    "progress.highlight.states." .. name .. ".fg must be a string",
                },
            })
        end

        if value.bg ~= nil then
            vim.validate({
                ["progress.highlight.states." .. name .. ".bg"] = {
                    value.bg,
                    "string",
                    "progress.highlight.states." .. name .. ".bg must be a string",
                },
            })
        end

        if value.gui ~= nil then
            vim.validate({
                ["progress.highlight.states." .. name .. ".gui"] = {
                    value.gui,
                    "string",
                    "progress.highlight.states." .. name .. ".gui must be a string",
                },
            })
        end
    end

    vim.validate({
        disable_all                 = {
            config.show_notification.disable_all,
            "boolean",
            "show_notification.disable_all must be a boolean",
        },
        when_finish_setup           = {
            config.show_notification.when_finish_setup,
            "boolean",
            "show_notification.when_finish_setup must be a boolean",
        },
        when_show_total_music_count = {
            config.show_notification.when_show_total_music_count,
            "boolean",
            "show_notification.when_show_total_music_count must be a boolean",
        },
        when_start_playing          = {
            config.show_notification.when_start_playing,
            "boolean",
            "show_notification.when_start_playing must be a boolean",
        },
        when_toogle_playing_state   = {
            config.show_notification.when_toogle_playing_state,
            "boolean",
            "show_notification.when_toogle_playing_state must be a boolean",
        },
    })

    vim.validate({
        mode                      = {
            config.mode,
            function(mode)
                return valid_modes[mode] == true
            end,
            "Invalid mode. Must be one of 'interval_random', 'interval_sequential', 'without_interval_random', 'without_interval_sequential', 'intermittently', 'continuous'",
        },
        min_ms                    = {
            config.interval.min_ms,
            function(value)
                return value > 0
            end,
            "interval.min_ms must be greater than 0",
        },
        max_ms                    = {
            config.interval.max_ms,
            function(value)
                return value > 0 and value >= config.interval.min_ms
            end,
            "interval.max_ms must be greater than 0 and no smaller than interval.min_ms",
        },
        volumn_percentage         = {
            config.volumn_percentage,
            function(value)
                return value >= 0 and value <= 100
            end,
            "volumn_percentage must be between 0 and 100",
        },
        recursive_depth           = {
            config.recursive_depth,
            function(value)
                return value > 0
            end,
            "recursive_depth must be greater than 0",
        },
        progress_width            = {
            config.progress.layout.width,
            function(value)
                return value >= 24 and value <= 80
            end,
            "progress.layout.width must be between 24 and 80",
        },
        progress_track_width      = {
            config.progress.track.width,
            function(value)
                return value >= 8 and value <= 60
            end,
            "progress.track.width must be between 8 and 60",
        },
        progress_bar_body_width   = {
            config.progress.bar.width,
            function(value)
                return value >= 4 and value <= 40
            end,
            "progress.bar.width must be between 4 and 40",
        },
        progress_refresh_interval = {
            config.progress.refresh.interval_ms,
            function(value)
                return value >= 100
            end,
            "progress.refresh.interval_ms must be at least 100",
        },
    })

    if type(config.playlists) == "table" then
        for _, item in ipairs(config.playlists) do
            vim.validate({
                playlist_path   = {
                    getPlaylistPath(item),
                    isUsablePathString,
                    "playlist path must be a non-empty path, not an angle-bracket placeholder",
                },
                playlist_ext    = {
                    item.ext,
                    isStringArray,
                    "playlist.ext must be a list of strings",
                },
                recursive_depth = {
                    item.recursive_depth,
                    "number",
                    "playlist.recursive_depth must be a number",
                },
                sort_field      = {
                    item.sort_field,
                    function(value)
                        return valid_sort_fields[value] == true
                    end,
                    "playlist.sort_field is invalid",
                },
                sort_direction  = {
                    item.sort_direction,
                    function(value)
                        return valid_sort_directions[value] == true
                    end,
                    "playlist.sort_direction must be 'asc' or 'desc'",
                },
            })
        end
    end
end

---@param opts? AmbientConfig
---@return AmbientResult<AmbientConfig, AmbientConfigError>
function M.setup(opts)
    local ok, err = pcall(function()
        local raw_opts        = opts or {}
        local base            = vim.deepcopy(default_config)
        local requested_style = base.progress.bar.style
        if type(raw_opts.progress) == "table" then
            if type(raw_opts.progress.bar) == "table" and raw_opts.progress.bar.style ~= nil then
                requested_style = raw_opts.progress.bar.style
            end
        end
        base.progress = progress_styles.apply(base.progress, requested_style)

        local merged = vim.tbl_deep_extend("force", base, raw_opts)
        validate(merged)
        normalize(merged)
        validate(merged)
        M.state.values = merged
    end)

    if not ok then
        M.state.ready   = false
        M.state.err     = M.Error.invalid_config
        M.state.err_msg = tostring(err)
        M.state.values  = nil
        return result.err(M.Error.invalid_config)
    end

    M.state.ready   = true
    M.state.err     = nil
    M.state.err_msg = nil
    return result.ok(M.state.values)
end
---@return AmbientResult<AmbientConfig, AmbientConfigError>
function M.get()
    if not M.state.ready then
        return result.err(M.Error.not_ready)
    end

    return result.ok(M.state.values)
end
---@return boolean
function M.is_ready()
    return M.state.ready
end
---@return string?
function M.get_error_message()
    return M.state.err_msg
end
return M
