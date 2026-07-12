local M = {}

-- old api compatibility
local uv     = vim.uv or vim.loop
local result = require("ambient.result")

---@enum AmbientMpvIpcError
M.Error = {
    mpv_not_found    = "mpv_not_found",
    mpv_start_failed = "mpv_start_failed",

    socket_wait_timeout   = "socket_wait_timeout",
    socket_connect_failed = "socket_connect_failed",

    write_failed = "write_failed",

    ipc_input_line_invalid = "ipc_input_line_invalid",
    ipc_read_failed        = "ipc_read_failed",
    ipc_json_decode_failed = "ipc_json_decode_failed",
    ipc_encode_failed      = "ipc_encode_failed",

    ipc_connect_failed = "ipc_connect_failed",
    ipc_write_failed   = "ipc_write_failed",
    ipc_decode_failed  = "ipc_decode_failed",

    ipc_invalid_state  = "invalid_state",
    request_timeout    = "request_timeout",
    mpv_command_failed = "mpv_command_failed",
}

---@enum AmbientMpvIpcState
M.State = {
    not_started  = "not_started",
    starting     = "starting",
    started      = "started",
    start_failed = "start_failed",
    closed       = "closed",
}

---@class AmbientMpvIpcConfig
---@field socket_wait_connect_timeout_ms integer
---@field socket_wait_ready_timeout_ms integer
---@field socket_wait_reply_timeout_ms integer

---@type AmbientMpvIpcConfig
M.Config = {
    socket_wait_ready_timeout_ms   = 1000,
    socket_wait_connect_timeout_ms = 1000,
    socket_wait_reply_timeout_ms   = 1000,
}

---@class AmbientMpvIpcReply
---@field error string
---@field data? any
---@field request_id integer

---@class AmbientMpvIpcClient
---@field state AmbientMpvIpcState
---@field job_id? integer
---@field socket_path? string
---@field pipe? uv.uv_pipe_t
---@field request_id integer
---@field recv_buf string
---@field pending table<integer, AmbientMpvIpcReply>
---@field events table[]

---@type AmbientMpvIpcClient
M.client = {
    state       = M.State.not_started,
    job_id      = nil,
    socket_path = nil,
    pipe        = nil,
    request_id  = 0,
    recv_buf    = "",
    pending     = {},
    events      = {},
}

---@class AmbientMpvIpcCommandItem
---@field args string[]
---@field make fun(socket_path: string): string[]

---@class AmbientMpvCommand
---@field start_cmd AmbientMpvIpcCommandItem
---
---@type AmbientMpvCommand
M.Command = {
    start_cmd = {
        args = {
            "mpv",
            "--idle=yes",
            "no-video",
            "--force-window=no",
            "--input-terminal=no",
            "terminal=no",
        },
        make = function(socket_path)
            local line = string.format("--input-ipc_server=%s", socket_path)
            return vim.list_extend(M.Command.start_cmd.args, { line })
        end,
    },
}

---@return integer
local function nextRequestId()
    M.client.request_id = M.client.request_id + 1
    return M.client.request_id
end

local function makeSocketPath()
    local base = "/tmp"
    return string.format("%s/ambient-mpv-%d.sock", base, uv.os_getpid())
end


local function handleIpcLine(line)
    if line == "" then
        return result.err(M.Error.ipc_input_line_invalid)
    end

    local ok, decoded = pcall(vim.json.decode, line)

    if not ok then
        table.insert(M.client.events, {
            event = "ambient-json-decode-error",
            raw   = line,
        })
        return result.err(M.Error.ipc_json_decode_failed)
    end

    -- if request_id is explicitly set, then this is a reply to a request.
    if decoded.request_id ~= nil then
        M.client.pending[decoded.request_id] = decoded
        return result.ok(decoded)
    end

    -- mpv event, like file-loaded/end-file/shutdown
    table.insert(M.client.events, decoded)
    return result.ok(nil)
end

---@param pipe uv.uv_pipe_t
---@return AmbientResult<nil, AmbientMpvIpcError>
local function startReadLoop(pipe)
    pipe:read_start(function(err, chunk)
        if err then
            table.insert(M.client.events, {
                event = "ambient-read-error",
                err   = err,
            })
            return
        end

        if chunk == nil then
            return
        end

        M.client.recv_buf = M.client.recv_buf .. chunk

        while true do
            local idx = M.client.recv_buf:find("\n", 1, true)
            if idx == nil then
                break;
            end
            local line        = M.client.recv_buf:sub(1, idx - 1)
            M.client.recv_buf = M.client.recv_buf:sub(idx + 1)

            handleIpcLine(line)
        end
    end)

    return result.ok(nil)
end

---@return AmbientResult<nil, AmbientMpvIpcError>
function M.start()
    if M.client.state ~= M.State.not_started and M.client.state ~= M.State.closed then
        return result.err(M.Error.ipc_invalid_state)
    end

    if vim.fn.executable("mpv") == 0 then
        return result.err(M.Error.mpv_not_found)
    end

    -- set the flag
    M.client.state    = M.State.starting
    local socket_path = makeSocketPath()
    pcall(vim.fn.delete, socket_path)

    ---@type table<string>
    local args = M.Command.start_cmd.make(socket_path)

    -- get the job id of the mpv process
    local job_id = vim.fn.jobstart(args, {
        detach  = false,
        on_exit = function(_, _) -- on exit callback
            M.client.state  = M.State.closed
            M.client.job_id = nil
            M.client.pipe   = nil
        end,
    })

    -- check the job id
    if job_id <= 0 then
        M.client.state = M.State.start_failed
        return result.err(M.Error.mpv_start_failed)
    end

    M.client.job_id      = job_id;
    M.client.socket_path = socket_path;

    local pipe = uv.new_pipe(false)

    if pipe == nil then
        M.stop()
        return result.err(M.Error.ipc_connect_failed)
    end

    local connected       = false
    local connected_error = nil

    pipe:connect(socket_path, function(err)
        if err then
            connected_error = err
            return
        end

        connected = true
        startReadLoop(pipe)
    end)

    -- wait for connection
    local connect_done = vim.wait(M.Config.socket_wait_connect_timeout_ms, function()
        return connected or connected_error ~= nil
    end, 10)

    if not connect_done or connected_error ~= nil then
        pcall(function() pipe:close() end)
        M.stop()
        return result.err(M.Error.socket_connect_failed)
    end

    M.client.pipe  = pipe
    M.client.state = M.State.started

    return result.ok(nil)
end

---@param command any[]
---@return AmbientResult<integer, AmbientMpvIpcError>
function M.send(command)
    if M.client.state ~= M.State.started then
        return result.err(M.Error.ipc_invalid_state)
    end

    local request_id  = nextRequestId()
    local ok, payload = pcall(vim.json.encode, {
        command    = command,
        request_id = request_id,
    })
    if not ok then
        return result.err(M.Error.ipc_encode_failed)
    end

    payload = payload .. "\n"

    local write_ok = true

    M.client.pipe:write(payload, function(err)
        if err then
            write_ok = false
        end
    end)

    if not write_ok then
        return result.err(M.Error.write_failed)
    end

    return result.ok(request_id)
end

---@param request_id integer
---@param timeout_ms? integer
---@return AmbientResult<AmbientMpvIpcReply, AmbientMpvIpcError>
function M.waitReply(request_id, timeout_ms)
    timeout_ms = timeout_ms or 1000

    local ok = vim.wait(timeout_ms, function()
        return M.client.pending[request_id] ~= nil
    end, 10)

    if not ok then
        return result.err(M.Error.request_timeout)
    end

    local reply                  = M.client.pending[request_id]
    M.client.pending[request_id] = nil

    if reply.error ~= "success" then
        return result.err(M.Error.mpv_command_failed)
    end

    return result.ok(reply)
end

---@param command any[]
---@param timeout_ms? integer
---@return AmbientResult<AmbientMpvIpcReply, AmbientMpvIpcError>
function M.request(command, timeout_ms)
    local sent = M.send(command)

    if not sent.ok then
        return sent
    end

    return M.waitReply(sent.value, timeout_ms)
end

---@return table[]
function M.drainEvent()
    local events    = M.client.events
    M.client.events = {}
    return events
end

---@return AmbientResult<nil, AmbientMpvIpcError>
function M.stop()
    if M.client.pipe ~= nil then
        pcall(function()
            M.client.pipe:read_stop()
            M.client.pipe:shutdown()
            M.client.pipe:close()
        end)
    end

    if M.client.job_id ~= nil then
        pcall(vim.fn.jobstop, M.client.job_id)
    end

    if M.client.socket_path ~= nil then
        pcall(vim.fn.delete, M.client.socket_path)
    end

    M.client.state       = M.State.closed
    M.client.job_id      = nil
    M.client.socket_path = nil
    M.client.pipe        = nil
    M.client.recv_buf    = ""
    M.client.pending     = {}
    M.client.events      = {}

    return result.ok(nil)
end

return M
