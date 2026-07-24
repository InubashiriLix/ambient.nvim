local t = require("tests.testlib")

local function loadIpc()
    local started_args
    local job_callbacks
    local socket_callbacks
    local encoded         = {}
    local sent_payloads   = {}
    local stopped_jobs    = {}
    local closed_channels = {}

    _G.vim = {
        uv          = {
            os_getpid = function()
                return 123
            end,
            fs_stat   = function()
                return { type = "socket" }
            end,
        },
        fn          = {
            executable  = function()
                return 1
            end,
            delete      = function()
                return 0
            end,
            jobstart    = function(args, callbacks)
                started_args  = args
                job_callbacks = callbacks
                return 7
            end,
            sockconnect = function(_, _, callbacks)
                socket_callbacks = callbacks
                return 9
            end,
            chansend    = function(_, payload)
                table.insert(sent_payloads, payload)
                return #payload
            end,
            chanclose   = function(channel)
                table.insert(closed_channels, channel)
            end,
            jobstop     = function(job)
                table.insert(stopped_jobs, job)
            end,
        },
        json        = {
            encode = function(value)
                table.insert(encoded, value)
                return "request-" .. tostring(value.request_id)
            end,
            decode = function(line)
                if line == "reply-ok" then
                    return {
                        request_id = 1,
                        error      = "success",
                        data       = "/music/a.mp3",
                    }
                elseif line == "reply-error" then
                    return {
                        request_id = 1,
                        error      = "property unavailable",
                    }
                elseif line == "file-loaded" then
                    return { event = "file-loaded" }
                end
                error("unexpected JSON fixture")
            end,
        },
        wait        = function(_, predicate)
            return predicate()
        end,
        schedule    = function(callback)
            callback()
        end,
        deepcopy    = function(value)
            local copied = {}
            for index, item in ipairs(value) do
                copied[index] = item
            end
            return copied
        end,
        list_extend = function(target, source)
            for _, item in ipairs(source) do
                table.insert(target, item)
            end
            return target
        end,
    }

    t.clearModules("ambient.mpv_ipc")
    local ipc = require("ambient.mpv_ipc")
    return ipc, {
        startedArgs     = function()
            return started_args
        end,
        socketCallbacks = function()
            return socket_callbacks
        end,
        jobCallbacks    = function()
            return job_callbacks
        end,
        encoded         = encoded,
        sent_payloads   = sent_payloads,
        stopped_jobs    = stopped_jobs,
        closed_channels = closed_channels,
    }
end

t.test("mpv IPC starts a headless cover-capable player", function()
    local ipc, env = loadIpc()

    local started = ipc.start()

    t.truthy(started.ok)
    t.eq(env.startedArgs(), {
        "mpv",
        "--no-config",
        "--idle=yes",
        "--audio-display=embedded-first",
        "--cover-art-auto=exact",
        "--vo=null",
        "--screenshot-sw=yes",
        "--force-window=no",
        "--input-terminal=no",
        "--terminal=no",
        "--input-ipc-server=/tmp/ambient-mpv-123.sock",
    })
    t.truthy(ipc.isStarted())

    ipc.stop()
    t.eq(env.closed_channels, { 9 })
    t.eq(env.stopped_jobs, { 7 })
end)

t.test("mpv IPC routes asynchronous replies separately from events", function()
    local ipc, env = loadIpc()
    ipc.start()

    local async_reply
    local requested = ipc.requestAsync({ "get_property", "path" }, function(reply)
        async_reply = reply
    end)
    t.truthy(requested.ok)
    t.eq(env.encoded[1], {
        command    = { "get_property", "path" },
        request_id = 1,
    })

    env.socketCallbacks().on_data(nil, { "reply-ok", "" }, nil)
    t.truthy(async_reply.ok)
    t.eq(async_reply.value.data, "/music/a.mp3")

    env.socketCallbacks().on_data(nil, { "file-loaded", "" }, nil)
    t.eq(ipc.drainEvent(), { { event = "file-loaded" } })
end)
