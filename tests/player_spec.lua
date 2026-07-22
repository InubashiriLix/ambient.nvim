local t = require("tests.testlib")

local function loadPlayer(options)
    options            = options or {}
    local now          = options.now or 1000
    local jobs         = {}
    local stopped_jobs = {}
    local killed       = {}

    _G.vim = {
        uv = {
            now       = function()
                return now
            end,
            kill      = function(pid, signal)
                table.insert(killed, { pid = pid, signal = signal })
            end,
            constants = { SIGSTOP = 19, SIGCONT = 18 },
        },

        fn = {
            exists     = function()
                return 1
            end,
            executable = function()
                return options.executable == false and 0 or 1
            end,
            jobpid     = function(job_id)
                return job_id + 1000
            end,
            jobstart   = function(args, callbacks)
                if options.job_id ~= nil and options.job_id <= 0 then
                    return options.job_id
                end
                local id = options.job_id or (#jobs + 1)
                jobs[id] = { args = args, callbacks = callbacks }
                return id
            end,
            jobstop    = function(job_id)
                table.insert(stopped_jobs, job_id)
            end,
        },

        deepcopy = function(value)
            local copied = {}
            for key, item in pairs(value) do
                copied[key] = item
            end
            return copied
        end,
    }

    t.clearModules("ambient.player")
    local player = require("ambient.player")
    return player,
        {
            jobs         = jobs,
            stopped_jobs = stopped_jobs,
            killed       = killed,
            setNow       = function(value)
                now = value
            end,
        }
end

local function music(name, duration)
    return {
        name              = name,
        abs_path          = "/music/" .. name .. ".wav",
        duration_ms       = duration or 10000,
        load_count        = 0,
        loadDurationAsync = function(self)
            self.load_count = self.load_count + 1
        end,
        setCursorTime     = function(self, value)
            self.cursor_time_ms = value
        end,
    }
end

t.test("player exposes a direct success/error contract", function()
    local player = loadPlayer({ executable = false })
    player:setup({ volume = 72 })
    local err = player:play(music("a"))

    t.eq(err, player.Error.MPV_NOT_FOUND)
    t.eq(player.state.state, player.STATE.ERROR)
    t.eq(player:get_error_message(), player.Error.MPV_NOT_FOUND)
end)

t.test("player starts, pauses, resumes, reports progress, and stops a job", function()
    local player, env = loadPlayer()
    local track       = music("a", 10000)
    player:setup({ volume = 65 })

    t.eq(player:play(track), nil)
    t.eq(env.jobs[1].args, {
        "mpv",
        "--no-video",
        "--force-window=no",
        "--input-terminal=no",
        "--terminal=no",
        "--volume=65",
        "/music/a.wav",
    })
    t.eq(track.load_count, 1)
    t.eq(player.state.state, player.STATE.PLAYING)

    env.setNow(3000)
    t.eq(player:getProgress(), { time_ms = 2000, duration_ms = 10000, percentage = 20 })
    t.eq(player:pause(), nil)
    t.eq(env.killed[1], { pid = 1001, signal = 19 })

    env.setNow(5000)
    t.eq(player:getProgress(), { time_ms = 2000, duration_ms = 10000, percentage = 20 })
    t.eq(player:resume(), nil)
    t.eq(env.killed[2], { pid = 1001, signal = 18 })

    env.setNow(7000)
    t.eq(player:getProgress(), { time_ms = 4000, duration_ms = 10000, percentage = 40 })
    player:stop()
    t.eq(env.stopped_jobs, { 1 })
    t.eq(player.state.state, player.STATE.STOPPED)
end)

t.test("player classifies natural, failed, and requested exits", function()
    local player, env = loadPlayer()
    player:setup({ volume = 50 })

    player:play(music("natural"))
    env.jobs[1].callbacks.on_exit(1, 0)
    t.eq(player:drainEvents(), { { event = "end-file", reason = "eof" } })

    player:play(music("failed"))
    env.jobs[2].callbacks.on_exit(2, 2)
    t.eq(player:drainEvents(), { { event = "end-file", reason = "error" } })

    player:play(music("stopped"))
    player:stop()
    env.jobs[3].callbacks.on_exit(3, 0)
    t.eq(player:drainEvents(), { { event = "end-file", reason = "stop" } })
end)

t.test("player reports startup and invalid pause/resume failures without Results", function()
    local player = loadPlayer({ job_id = -1 })
    player:setup({ volume = 50 })
    t.eq(player:pause(), player.Error.NOT_READY)
    t.eq(player:resume(), player.Error.NOT_READY)
    t.eq(player:play(music("a")), player.Error.MPV_START_FAILED)
end)
