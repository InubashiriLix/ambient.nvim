local M = {}

---@class AmbientIntervalConfig
---@field min_ms integer
---@field max_ms integer

---@class AmbientShowNotificationConfig
---@field disable_all boolean
---@field when_finish_setup boolean
---@field show_total_music_count boolean
---@field when_start_playing boolean
---@field when_toogle_playing_state boolean

---@alias ambient_play_mode "interval_random" | "interval_sequential" | "without_interval_random" | "without_interval_sequential"

---@class AmbientConfig
---@field enable boolean
---@field mode ambient_play_mode
---@field music_dir string
---@field volumn_percentage integer
---@field interval AmbientIntervalConfig
---@field show_notification AmbientShowNotificationConfig

return M
