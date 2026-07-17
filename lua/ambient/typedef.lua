local M = {}

---@class AmbientIntervalConfig
---@field min_ms integer
---@field max_ms integer

---@class AmbientShowNotificationConfig
---@field disable_all boolean
---@field when_finish_setup boolean
---@field when_show_total_music_count boolean
---@field when_start_playing boolean
---@field when_toggle_playing_state boolean
---@field when_toogle_playing_state? boolean Deprecated misspelling kept for existing configs.

---@alias AmbientPlayMode "interval_random" | "interval_sequential" | "without_interval_random" | "without_interval_sequential" | "intermittently" | "continuous" | "continously"

---@class AmbientPlaylistConfig
---@field abs_path string
---@field ext string[]
---@field recursive_depth integer
---@field sort_field SortField
---@field sort_direction SortDirection

---@alias AmbientProgressCanonicalStyle
---| "braille"
---| "block"
---| "line"
---| "dots"
---| "squares"
---| "diamonds"
---| "pipes"
---| "ascii"
---| "brackets"
---| "angle"
---| "powerline"
---| "separators"
---| "rounded"
---| "slanted"

---@alias AmbientProgressStyle
---| "braille"
---| "block"
---| "line"
---| "dots"
---| "squares"
---| "diamonds"
---| "pipes"
---| "ascii"
---| "brackets"
---| "angle"
---| "powerline"
---| "separators"
---| "rounded"
---| "slanted"
---| "default"
---| "sparse"
---| "classic"
---| "blocks"
---| "dense"
---| "old"
---| "bracket"
---| "dot"
---| "square"
---| "diamond"
---| "pipe"
---| "separator"
---| "segment"
---| "bubble"
---| "round"

---@class AmbientProgressConfig
---@field enabled boolean Whether the statusline progress component starts visible.
---@field layout AmbientProgressLayoutConfig Whole component width and placement.
---@field track AmbientProgressTrackConfig Current track name rendering.
---@field bar AmbientProgressBarConfig Progress bar shape and style.
---@field time AmbientProgressTimeConfig Elapsed/total time rendering.
---@field refresh AmbientProgressRefreshConfig Statusline refresh cadence.
---@field component AmbientProgressComponentConfig Statusline component integration.
---@field highlight AmbientProgressHighlightConfig Default and per-state colors.

---@alias AmbientProgressBarStyle
---| "none"
---| "bold"
---| "italic"
---| "underline"
---| "undercurl"
---| "strikethrough"

---@class AmbientProgressLayoutConfig
---@field width integer Fixed display width of ambient's statusline text; lualine separators and padding are outside it.

---@class AmbientProgressTrackConfig
---@field width integer Maximum display width for the current track name.
---@field scroll boolean Scroll long track names instead of truncating them.
---@field scroll_separator string Text inserted between repeated track names.

---@class AmbientProgressBarConfig
---@field style AmbientProgressStyle Built-in style preset for the progress bar itself.
---@field width integer Display width of the progress bar body, excluding left/right wrappers.
---@field filled string Filled cell character. Must occupy one display cell.
---@field empty string Empty cell character. Must occupy one display cell.
---@field left string Left wrapper for the progress bar only.
---@field right string Right wrapper for the progress bar only.

---@class AmbientProgressTimeConfig
---@field enabled boolean Show elapsed/total time before the progress bar.

---@class AmbientProgressRefreshConfig
---@field interval_ms integer Statusline refresh interval in milliseconds.

---@class AmbientProgressComponentConfig
---@field frame AmbientProgressFrameConfig Optional text wrapper rendered inside layout.width.
---@field separator? AmbientProgressLualineSeparatorConfig lualine separator override for this component. Omit to inherit lualine defaults.
---@field padding? integer|AmbientProgressLualinePaddingConfig lualine padding override for this component. Omit to inherit lualine defaults.

---@class AmbientProgressHighlightConfig
---@field default AmbientProgressColorConfig Default lualine color table.
---@field states AmbientProgressColorsConfig Per-state color overrides.

---@class AmbientProgressColorConfig
---@field fg string
---@field bg string
---@field gui AmbientProgressBarStyle

---@class AmbientProgressColorsConfig
---@field default? AmbientProgressColorConfig
---@field ready? AmbientProgressColorConfig
---@field playing? AmbientProgressColorConfig
---@field interval? AmbientProgressColorConfig
---@field stopped? AmbientProgressColorConfig
---@field paused? AmbientProgressColorConfig
---@field next? AmbientProgressColorConfig
---@field error? AmbientProgressColorConfig

---@class AmbientProgressFrameConfig
---@field enabled boolean
---@field left string
---@field right string
---@field padding string

---@class AmbientProgressLualineSeparatorConfig
---@field left string
---@field right string

---@class AmbientProgressLualinePaddingConfig
---@field left? integer
---@field right? integer

---@class AmbientConfig
---@field enable boolean
---@field mode AmbientPlayMode
---@field music_dir string
---@field music_dirs? string[]
---@field playlists? AmbientPlaylistConfig[]
---@field extensions string[]
---@field recursive_depth integer
---@field volume? integer
---@field volumn_percentage? integer
---@field progress AmbientProgressConfig
---@field interval AmbientIntervalConfig
---@field show_notifications? boolean
---@field show_notification AmbientShowNotificationConfig

return M
