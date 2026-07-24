local t      = require("tests.testlib")
local result = require("ambient.result")

local function loadPlayer(options)
    options = options or {}

    local now            = options.now or 1000
    local started        = false
    local stop_count     = 0
    local requests       = {}
    local async_requests = {}
    local events         = {}
    local deleted        = {}
    local user_events    = {}
    local temp_index     = 0

    local ipc = {
        Error  = {
            mpv_not_found = "mpv_not_found",
        },
        client = {
            job_id = 71,
        },
    }

    function ipc.isStarted()
        return started
    end

    function ipc.start()
        if options.start_error ~= nil then
            return result.err(options.start_error)
        end
        started = true
        return result.ok(nil)
    end

    function ipc.stop()
        started    = false
        stop_count = stop_count + 1
        return result.ok(nil)
    end

    function ipc.request(command)
        table.insert(requests, command)
        if options.command_error ~= nil
            and command[1] == options.command_error
        then
            return result.err("command failed")
        end
        return result.ok({
            error      = "success",
            data       = nil,
            request_id = #requests,
        })
    end

    function ipc.requestAsync(command, callback)
        table.insert(async_requests, {
            command  = command,
            callback = callback,
        })
        return result.ok(#async_requests)
    end

    function ipc.drainEvent()
        local drained = events
        events        = {}
        return drained
    end

    _G.vim = {
        uv       = {
            now = function()
                return now
            end,
        },
        fn       = {
            tempname = function()
                temp_index = temp_index + 1
                return "/tmp/ambient-cover-" .. tostring(temp_index)
            end,
            delete   = function(path)
                table.insert(deleted, path)
                return 0
            end,
        },
        deepcopy = function(value)
            local copied = {}
            for key, item in pairs(value) do
                copied[key] = item
            end
            return copied
        end,
        api = {
            nvim_exec_autocmds = function(event, opts)
                if event == "User" then
                    table.insert(user_events, opts.pattern)
                end
            end,
        },
    }

    package.loaded["ambient.mpv_ipc"] = ipc
    t.clearModules("ambient.player")
    local player = require("ambient.player")

    return player, {
        ipc            = ipc,
        requests       = requests,
        async_requests = async_requests,
        deleted        = deleted,
        user_events    = user_events,
        queueEvent     = function(event)
            table.insert(events, event)
        end,
        resolveAsync   = function(index, data)
            async_requests[index].callback(result.ok({
                error      = "success",
                data       = data,
                request_id = index,
            }))
        end,
        rejectAsync    = function(index)
            async_requests[index].callback(result.err("command failed"))
        end,
        setNow         = function(value)
            now = value
        end,
        stopCount      = function()
            return stop_count
        end,
    }
end

local function music(name, duration)
    return {
        name              = name,
        abs_path          = "/music/" .. name .. ".mp3",
        duration_ms       = duration or 10000,
        load_count        = 0,
        release_count     = 0,
        album_name        = nil,
        artist_name       = nil,
        cover_pic         = nil,
        loadDurationAsync = function(self)
            self.load_count = self.load_count + 1
        end,
        releaseCoverPic   = function(self)
            self.release_count = self.release_count + 1
            if self.cover_pic ~= nil and self.cover_pic.temporary then
                vim.fn.delete(self.cover_pic.path)
            end
            self.cover_pic = nil
            return result.ok(nil)
        end,
        setCursorTime     = function(self, value)
            self.cursor_time_ms = value
        end,
    }
end

t.test("player maps mpv IPC startup failures", function()
    local player = loadPlayer({ start_error = "mpv_not_found" })
    player:setup({ volume = 72 })

    local err = player:play(music("a"))

    t.eq(err, player.Error.MPV_NOT_FOUND)
    t.eq(player.state.state, player.STATE.ERROR)
    t.eq(player:get_error_message(), player.Error.MPV_NOT_FOUND)
end)

t.test("player controls playback and progress through mpv IPC", function()
    local player, env = loadPlayer()
    local track       = music("a", 10000)
    player:setup({ volume = 65 })

    t.eq(player:play(track), nil)
    t.eq(env.requests[1], { "set_property", "volume", 65 })
    t.eq(env.requests[2], { "loadfile", "/music/a.mp3", "replace" })
    t.eq(track.load_count, 1)
    t.eq(player.state.state, player.STATE.PLAYING)

    env.setNow(3000)
    t.eq(player:getProgress(), {
        time_ms     = 2000,
        duration_ms = 10000,
        percentage  = 20,
    })
    t.eq(player:pause(), nil)
    t.eq(env.requests[3], { "set_property", "pause", true })

    env.setNow(5000)
    t.eq(player:getProgress(), {
        time_ms     = 2000,
        duration_ms = 10000,
        percentage  = 20,
    })
    t.eq(player:resume(), nil)
    t.eq(env.requests[4], { "set_property", "pause", false })

    env.setNow(7000)
    t.eq(player:getProgress(), {
        time_ms     = 4000,
        duration_ms = 10000,
        percentage  = 40,
    })

    player:stop()
    t.eq(env.requests[5], { "stop" })
    t.eq(track.release_count, 1)
    t.eq(player.state.state, player.STATE.STOPPED)
end)

t.test("player loads metadata and an owned cover after file-loaded", function()
    local player, env = loadPlayer()
    local track       = music("with-cover")
    player:setup({ volume = 50 })
    player:play(track)

    env.queueEvent({ event = "file-loaded" })
    t.eq(player:drainEvents(), {})
    t.eq(env.async_requests[1].command, { "get_property", "path" })

    env.resolveAsync(1, track.abs_path)
    t.eq(env.async_requests[2].command, { "get_property", "metadata" })
    t.eq(env.async_requests[3].command, { "get_property", "track-list" })

    env.resolveAsync(2, {
        ARTIST = "Artist",
        ALBUM  = "Album",
    })
    t.eq(track.artist_name, "Artist")
    t.eq(track.album_name, "Album")
    t.eq(env.user_events, { "AmbientTrackInfoUpdated" })

    env.resolveAsync(3, {
        {
            type        = "video",
            albumart    = true,
            selected    = true,
            external    = false,
            ["demux-w"] = 640,
            ["demux-h"] = 640,
        },
    })
    t.eq(env.async_requests[4].command, {
        "screenshot-to-file",
        "/tmp/ambient-cover-1.png",
        "video",
    })

    env.resolveAsync(4)
    t.eq(track.cover_pic, {
        path      = "/tmp/ambient-cover-1.png",
        mime      = "image/png",
        width     = 640,
        height    = 640,
        source    = "embedded",
        temporary = true,
    })
    t.eq(env.user_events, {
        "AmbientTrackInfoUpdated",
        "AmbientTrackInfoUpdated",
    })

    env.queueEvent({ event = "end-file", reason = "eof" })
    t.eq(player:drainEvents(), {
        { event = "end-file", reason = "eof" },
    })
    t.eq(track.cover_pic, nil)
    t.eq(env.deleted, { "/tmp/ambient-cover-1.png" })
    t.eq(player.state.current, nil)
end)

t.test("player rejects stale cover callbacks after switching tracks", function()
    local player, env = loadPlayer()
    local first       = music("first")
    local second      = music("second")
    player:setup({ volume = 50 })
    player:play(first)

    env.queueEvent({ event = "file-loaded" })
    player:drainEvents()
    env.resolveAsync(1, first.abs_path)
    env.resolveAsync(3, {
        {
            type     = "video",
            albumart = true,
            selected = true,
            external = false,
        },
    })

    player:play(second)
    env.resolveAsync(4)

    t.eq(first.cover_pic, nil)
    t.eq(second.cover_pic, nil)
    t.eq(env.deleted, {
        "/tmp/ambient-cover-1.png",
        "/tmp/ambient-cover-1.png",
    })
end)

t.test("player ignores replaced end events but releases failed tracks", function()
    local player, env = loadPlayer()
    local first       = music("first")
    local second      = music("second")
    player:setup({ volume = 50 })
    player:play(first)
    player:play(second)

    local releases_before = second.release_count
    env.queueEvent({ event = "end-file", reason = "stop" })
    player:drainEvents()
    t.eq(second.release_count, releases_before)
    t.eq(player.state.current, second)

    env.queueEvent({ event = "end-file", reason = "error" })
    player:drainEvents()
    t.eq(second.release_count, releases_before + 1)
    t.eq(player.state.current, nil)
end)

t.test("player shuts down its persistent mpv IPC process", function()
    local player, env = loadPlayer()
    local track       = music("a")
    player:setup({ volume = 50 })
    player:play(track)

    player:shutdown()

    t.eq(track.release_count, 1)
    t.eq(env.stopCount(), 1)
    t.eq(player.state.job_id, nil)
    t.eq(player.state.state, player.STATE.STOPPED)
end)

t.test("player reports command and invalid pause/resume failures", function()
    local player = loadPlayer({ command_error = "loadfile" })
    player:setup({ volume = 50 })
    t.eq(player:pause(), player.Error.NOT_READY)
    t.eq(player:resume(), player.Error.NOT_READY)
    t.eq(player:play(music("a")), player.Error.MPV_COMMAND_FAILED)
end)
