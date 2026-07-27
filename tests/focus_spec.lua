local t      = require("tests.testlib")
local result = require("ambient.common.result")

local function loadFocus(options)
    options = options or {}

    local timers       = {}
    local setup_count  = 0
    local played_music = nil
    local stop_count   = 0
    local user_events  = {}

    local timer = {}
    function timer.new(time_ms, callback)
        local instance = {
            time_ms     = time_ms,
            callback    = callback,
            started     = false,
            start_count = 0,
        }

        function instance:start()
            if options.timer_start_error ~= nil then
                return result.err(options.timer_start_error)
            end
            self.started     = true
            self.start_count = self.start_count + 1
            return result.ok(nil)
        end

        table.insert(timers, instance)
        return result.ok(instance)
    end

    local focus_music = {
        name     = "focus",
        abs_path = "/music/focus.ogg",
    }
    local relax_music = {
        name     = "relax",
        abs_path = "/music/relax.ogg",
    }

    local function playlistWithCurrent(current)
        return {
            getCurrent = function()
                return current
            end,
            hasNext   = function()
                return false
            end,
            reset     = function() end,
        }
    end

    local playlist = {
        SortField = {
            random = "random",
        },
        SortDirection = {
            asc = "asc",
        },
    }

    function playlist:new(path)
        if path == "focus" then
            local current = focus_music
            if options.empty then
                current = nil
            end
            return result.ok(playlistWithCurrent(current))
        end
        return result.ok(playlistWithCurrent(relax_music))
    end

    local player = {
        STATE = {
            NOT_READY = "NOT_READY",
            READY     = "READY",
            PLAYING   = "PLAYING",
        },
        state = {
            state = options.player_state or "NOT_READY",
        },
    }

    function player:setup()
        setup_count      = setup_count + 1
        self.state.state = self.STATE.READY
    end

    function player:play(music)
        if options.player_error ~= nil then
            return options.player_error
        end
        played_music    = music
        self.state.state = self.STATE.PLAYING
        return nil
    end

    function player:stop()
        stop_count      = stop_count + 1
        self.state.state = self.STATE.READY
    end

    function player:drainEvents()
        return {}
    end

    _G.vim = {
        log = {
            levels = {
                ERROR = 1,
            },
        },
        fn = {
            fnamemodify = function()
                return "."
            end,
        },
        api = {
            nvim_exec_autocmds = function(event, opts)
                if event == "User" then
                    table.insert(user_events, opts.pattern)
                end
            end,
        },
        defer_fn = function() end,
        notify = function() end,
    }

    package.loaded["ambient.common.timer"]    = timer
    package.loaded["ambient.models.playlist"] = playlist
    package.loaded["ambient.player"]          = player
    package.loaded["ambient.bonus.focus"]     = nil

    local focus = require("ambient.bonus.focus")
    return focus, {
        timers      = timers,
        focus_music = focus_music,
        relax_music = relax_music,
        setupCount  = function()
            return setup_count
        end,
        playedMusic = function()
            return played_music
        end,
        stopCount   = function()
            return stop_count
        end,
        userEvents  = user_events,
    }
end

t.test("focus epoch starts playback and its focus timer", function()
    local focus, env = loadFocus()

    t.truthy(focus:init(100, 20, "focus", "relax").ok)
    local started = focus:startOneFocusEpoch()

    t.truthy(started.ok)
    t.eq(focus.state, focus.State.FOCUS)
    t.eq(env.setupCount(), 1)
    t.eq(env.playedMusic(), env.focus_music)
    t.truthy(env.timers[1].started)
end)

t.test("focus epoch requires initialization and an idle state", function()
    local focus = loadFocus()
    t.eq(focus:startOneFocusEpoch().err, focus.StartError.NOT_INITIALIZED)

    t.truthy(focus:init(100, 20, "focus", "relax").ok)
    t.truthy(focus:startOneFocusEpoch().ok)
    t.eq(focus:startOneFocusEpoch().err, focus.StartError.ALREADY_RUNNING)
end)

t.test("focus epoch rejects an empty playlist", function()
    local focus = loadFocus({ empty = true })

    t.truthy(focus:init(100, 20, "focus", "relax").ok)
    t.eq(focus:startOneFocusEpoch().err, focus.StartError.EMPTY_PLAYLIST)
    t.eq(focus.state, focus.State.IDLE)
end)

t.test("focus epoch rolls playback back when its timer cannot start", function()
    local focus, env = loadFocus({ timer_start_error = "timer failed" })

    t.truthy(focus:init(100, 20, "focus", "relax").ok)
    t.eq(focus:startOneFocusEpoch().err, "timer failed")
    t.eq(focus.state, focus.State.IDLE)
    t.eq(env.stopCount(), 1)
end)

t.test("one focus trigger runs one focus-relax cycle", function()
    local focus, env = loadFocus()

    t.truthy(focus:init(100, 20, "focus", "relax").ok)
    t.truthy(focus:startOneFocusEpoch().ok)

    env.timers[1].callback()
    t.eq(focus.state, focus.State.RELAX)
    t.eq(env.playedMusic(), env.relax_music)
    t.eq(env.timers[2].start_count, 1)

    env.timers[2].callback()
    t.eq(focus.state, focus.State.IDLE)
    t.eq(env.playedMusic(), env.focus_music)
    t.eq(env.timers[1].start_count, 1)
    t.eq(env.userEvents, {
        "AmbientTrackChanged",
        "AmbientTrackChanged",
        "AmbientTrackChanged",
    })

    t.truthy(focus:startOneFocusEpoch().ok)
    t.eq(env.timers[1].start_count, 2)
end)
