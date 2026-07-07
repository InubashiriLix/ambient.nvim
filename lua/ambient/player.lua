local M = {}
--- this module should search the selected engine in the system and use it to play music, currently only support mpv
--- 1. validate the engine is reachable now
--- 2. load the engine
--- 3.

local result = require("ambient.result")

---@enum AmbientPlayerError
M.Error = {
    not_ready = "not_ready",

    engine_not_found = "engine_not_found",
    engine_start_failed_unknown = "engine_start_err",

    file_not_reachable = "file_not_reachable",
    file_load_failed_unknown = "file_load_failed_unknown",

    play_failed_unknown = "play_failed_unknown",

    job_id_not_found = "job_id_not_found",
    job_id_mismatch = "job_id_mismatch",

    pause_failed_unknown = "pause_failed_unknown",
    stop_failed_unknown = "stop_failed_unknown",
    continue_failed_unknown = "continue_failed_unknown",
}

---@enum AmbientPlayerState
M.State = {
    not_ready = "not_ready",
    ready = "ready",
    loading_file = "loading",
    playing = "playing",
    stopped = "stopped",
}

---@class MusicInfo
---@field file_path string
---@field title string
---@field total_duration_ms integer
---@field current_position_ms integer

---@class MusicPlayer
---@field engine_name string
---@field state AmbientPlayerState
---@field current_music_info? MusicInfo
---@field err AmbientPlayerError
---@field err_msg string

---@type MusicPlayer
M.player = {
    engine_name = "mpv",
    state = M.State.not_ready,


}

function M.setup()

end
return M
