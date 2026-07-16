local M = {}

local result = require("ambient.result")
local ipc    = require("ambient.mpv_ipc")

---@class AmbientPlayerCommandsItem
---@field command string | string[]
---@field args? string[]
---@field make fun(): string | string[]
---@field description string

---@alias AmbientPlayerCommands AmbientPlayerCommandsItem[]

---@type AmbientPlayerCommands
M.CMDS = {
    song_now_play_or_continue = {
        description = "Play or continue the current song or song to be played but not started yet",
    },
    song_now_play_next        = {
        description = "Play the next song now",
    },
    song_now_pause            = {
        description = "Pause the current song now, can be continued with song_now_play_or_continue",
    },
    song_now_stop             = {
        description =
        "Stop the current song now, change to next song if any, can be continued with song_now_play_or_continue",
    },
}

---@enum AmbientPlayerState
M.STATE = {
    NOT_READY = "NOT_READY",
    READY     = "READY",
    LOADING   = "LOADING",
    PLAYING   = "PLAYING",
    STOPPED   = "STOPPED",
    PAUSED    = "PAUSED",
    ERROR     = "ERROR",
}

---@class AmbientPlayer
---@field state AmbientPlayerState
---@filed
