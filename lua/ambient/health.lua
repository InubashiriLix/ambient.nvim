local M = {}

local config = require("ambient.config")

local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

local function checkExecutable(name, required)
    if vim.fn.executable(name) == 1 then
        ok(name .. " is installed")
        return
    end

    if required then
        error(name .. " is not installed")
    else
        warn(name .. " is not installed")
    end
end

function M.check()
    start("ambient.nvim")

    checkExecutable("mpv", true)
    checkExecutable("ffprobe", false)

    local cfg = config.get()
    if not cfg.ok then
        warn("ambient.nvim has not been configured yet")
        return
    end

    info("mode: " .. cfg.value.mode)
    info("volume: " .. tostring(cfg.value.volume or cfg.value.volumn_percentage))

    for _, item in ipairs(cfg.value.playlists or {}) do
        local stat = vim.uv.fs_stat(item.abs_path)
        if stat == nil then
            error("music directory does not exist: " .. item.abs_path)
        elseif stat.type ~= "directory" then
            error("music path is not a directory: " .. item.abs_path)
        else
            ok("music directory exists: " .. item.abs_path)
        end
    end
end

return M
