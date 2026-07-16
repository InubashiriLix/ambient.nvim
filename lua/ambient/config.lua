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
    volumn_percentage = 50,

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

---@param config AmbientConfig
local function validate(config)
    vim.validate({
        enable            = { config.enable, "boolean", "enable must be a boolean" },
        mode              = { config.mode, "string", "mode must be a string" },
        music_dir         = { config.music_dir, "string", "music_dir must be a string" },
        volumn_percentage = {
            config.volumn_percentage,
            "number",
            "volumn_percentage must be a number",
        },
        interval          = { config.interval, "table", "interval must be a table" },
        show_notification = {
            config.show_notification,
            "table",
            "show_notification must be a table",
        },
    })

    vim.validate({
        min_ms = { config.interval.min_ms, "number", "interval.min_ms must be a number" },
        max_ms = { config.interval.max_ms, "number", "interval.max_ms must be a number" },
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
                return mode == "interval_random"
                    or mode == "interval_sequential"
                    or mode == "without_interval_random"
                    or mode == "without_interval_sequential"
            end,
            "Invalid mode. Must be one of 'interval_random', 'interval_sequential', 'without_interval_random', 'without_interval_sequential'",
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
    })
end

---@param opts? AmbientConfig
---@return AmbientResult<AmbientConfig, AmbientConfigError>
function M.setup(opts)
    local ok, err = pcall(function()
        local merged = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})
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
