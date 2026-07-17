local M = {}

---@class AmbientIntervalConfig
---@field min_ms integer
---@field max_ms integer

---@class AmbientShowNotificationConfig
---@field disable_all boolean
---@field when_finish_setup boolean
---@field when_show_total_music_count boolean
---@field when_start_playing boolean
---@field when_toogle_playing_state boolean

---@alias AmbientPlayMode "interval_random" | "interval_sequential" | "without_interval_random" | "without_interval_sequential" | "intermittently" | "continuous" | "continously"

---@class AmbientPlaylistConfig
---@field abs_path string
---@field ext string[]
---@field recursive_depth integer
---@field sort_field SortField
---@field sort_direction SortDirection

---@class AmbientProgressConfig
---@field enabled boolean
---@field width integer
---@field update_interval_ms integer
---@field color AmbientProgressColorConfig

---@alias AmbientProgressBarStyle
---| "none"
---| "bold"
---| "italic"
---| "underline"
---| "undercurl"
---| "strikethrough"

---@class AmbientProgressColorConfig
---@field fg string
---@field bg string
---@field gui AmbientProgressBarStyle

---@class AmbientConfig
---@field enable boolean
---@field mode AmbientPlayMode
---@field music_dir string
---@field music_dirs? string[]
---@field playlists AmbientPlaylistConfig[]
---@field extensions string[]
---@field recursive_depth integer
---@field volume integer
---@field volumn_percentage integer
---@field progress AmbientProgressConfig
---@field interval AmbientIntervalConfig
---@field show_notification AmbientShowNotificationConfig

return M
