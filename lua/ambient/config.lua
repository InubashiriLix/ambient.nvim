local M = {}

local result = require("ambient.result")

---@enum AmbientConfigError
M.Error = {
    invalid_config = "invalid_config",
    not_ready      = "not_ready",
}

---@type AmbientConfig
local default_config = {
    enable            = true,
    mode              = "interval_random",
    music_dir         = "~/.config/nvim/ambient.music",
    music_dirs        = nil,
    playlists         = nil,
    extensions        = { "mp3", "ogg", "flac", "wav", "m4a", "aac", "opus" },
    recursive_depth   = 4,
    volume            = nil,
    show_notifications = nil,
    volumn_percentage = 50,
    progress          = {
        enabled            = false,
        width              = 42,
        update_interval_ms = 500,
        color              = {
            fg  = "#ffffff",
            bg  = "#5b7ee5",
            gui = "bold",
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
        config.show_notification.when_toogle_playing_state = config.show_notification.when_toggle_playing_state
    end

    if config.progress.enable ~= nil then
        config.progress.enabled = config.progress.enable
    end

    config.extensions = normalizeExtensions(config.extensions)

    local playlist_defaults = {
        ext             = config.extensions,
        recursive_depth = config.recursive_depth,
        sort_field      = (config.mode == "interval_sequential" or config.mode == "without_interval_sequential") and "name"
            or "random",
        sort_direction  = "asc",
    }

    local playlists = {}

    if type(config.playlists) == "table" then
        for _, item in ipairs(config.playlists) do
            table.insert(playlists, {
                abs_path        = normalizePath(item.abs_path or item.path or item.dir),
                ext             = normalizeExtensions(item.ext or item.extensions or playlist_defaults.ext),
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
        music_dir         = { config.music_dir, "string", "music_dir must be a string" },
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
                isStringArray,
                "music_dirs must be a list of strings",
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
        progress_enabled            = {
            config.progress.enabled,
            "boolean",
            "progress.enabled must be a boolean",
        },
        progress_width              = {
            config.progress.width,
            "number",
            "progress.width must be a number",
        },
        progress_update_interval_ms = {
            config.progress.update_interval_ms,
            "number",
            "progress.update_interval_ms must be a number",
        },
        progress_color              = {
            config.progress.color,
            "table",
            "progress.color must be a table",
        },
        progress_color_fg           = {
            config.progress.color.fg,
            "string",
            "progress.color.fg must be a string",
        },
        progress_color_bg           = {
            config.progress.color.bg,
            "string",
            "progress.color.bg must be a string",
        },
        progress_color_gui          = {
            config.progress.color.gui,
            "string",
            "progress.color.gui must be a string",
        },
    })

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
        mode              = {
            config.mode,
            function(mode)
                return valid_modes[mode] == true
            end,
            "Invalid mode. Must be one of 'interval_random', 'interval_sequential', 'without_interval_random', 'without_interval_sequential', 'intermittently', 'continuous'",
        },
        min_ms            = {
            config.interval.min_ms,
            function(value)
                return value > 0
            end,
            "interval.min_ms must be greater than 0",
        },
        max_ms            = {
            config.interval.max_ms,
            function(value)
                return value > 0 and value >= config.interval.min_ms
            end,
            "interval.max_ms must be greater than 0 and no smaller than interval.min_ms",
        },
        volumn_percentage = {
            config.volumn_percentage,
            function(value)
                return value >= 0 and value <= 100
            end,
            "volumn_percentage must be between 0 and 100",
        },
        recursive_depth   = {
            config.recursive_depth,
            function(value)
                return value > 0
            end,
            "recursive_depth must be greater than 0",
        },
        progress_width    = {
            config.progress.width,
            function(value)
                return value >= 24 and value <= 80
            end,
            "progress.width must be between 24 and 80",
        },
        progress_update_interval_ms = {
            config.progress.update_interval_ms,
            function(value)
                return value >= 100
            end,
            "progress.update_interval_ms must be at least 100",
        },
    })

    if type(config.playlists) == "table" then
        for _, item in ipairs(config.playlists) do
            vim.validate({
                playlist_abs_path = {
                    item.abs_path,
                    "string",
                    "playlist.abs_path must be a string",
                },
                playlist_ext      = {
                    item.ext,
                    isStringArray,
                    "playlist.ext must be a list of strings",
                },
                recursive_depth   = {
                    item.recursive_depth,
                    "number",
                    "playlist.recursive_depth must be a number",
                },
                sort_field        = {
                    item.sort_field,
                    function(value)
                        return valid_sort_fields[value] == true
                    end,
                    "playlist.sort_field is invalid",
                },
                sort_direction    = {
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
        local merged = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})
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
