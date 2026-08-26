local result = require("ambient.common.result")

---@enum AmbientResumeStateError
local Error = {
    NO_SAVED_STATE      = "NO_SAVED_STATE",
    INVALID_SAVED_STATE = "INVALID_SAVED_STATE",
    IO_ERROR            = "RESUME_STATE_IO_ERROR",
}

local M = { Error = Error }

local function statePath()
    return vim.fn.stdpath("state") .. "/ambient.nvim/resume.json"
end

function M.save(snapshot)
    local directory = vim.fn.fnamemodify(statePath(), ":h")
    if vim.fn.mkdir(directory, "p") ~= 1 and vim.fn.isdirectory(directory) ~= 1 then
        return result.err(Error.IO_ERROR)
    end
    local encoded_ok, encoded = pcall(vim.json.encode, snapshot)
    if not encoded_ok then return result.err(Error.INVALID_SAVED_STATE) end
    local file = io.open(statePath(), "w")
    if file == nil then return result.err(Error.IO_ERROR) end
    local written_ok = file:write(encoded)
    file:close()
    return written_ok and result.ok(nil) or result.err(Error.IO_ERROR)
end

function M.load()
    local file = io.open(statePath(), "r")
    if file == nil then return result.err(Error.NO_SAVED_STATE) end
    local contents = file:read("*a")
    file:close()
    local decoded_ok, decoded = pcall(vim.json.decode, contents)
    if not decoded_ok or type(decoded) ~= "table" then
        return result.err(Error.INVALID_SAVED_STATE)
    end
    return result.ok(decoded)
end

return M
