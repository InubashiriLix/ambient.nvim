local t = require("tests.testlib")
local result = require("ambient.result")

local function loadAmbient(options)
    options = options or {}
    local commands = {}
    local notifications = {}
    local refresh_count = 0
    local cfg = options.config
        or {
            enable = true,
            show_notification = {
                disable_all = true,
                when_finish_setup = false,
                when_show_total_music_count = false,
            },
        }

    local config = {
        ready = options.ready ~= false,
    }
    function config.is_ready()
        return config.ready
    end
    function config.get()
        return options.config_result or result.ok(cfg)
    end
    function config.setup()
        config.ready = true
        return options.setup_result or result.ok(cfg)
    end
    function config.get_error_message()
        return "invalid config"
    end

    local schedule = {
        State = { PLAYING = "PLAYING", INTERVAL = "INTERVAL" },
        ready = options.schedule_ready ~= false,
        status_value = {
            state = "PLAYING",
            playlist_count = 1,
            total_music_count = 3,
            current_music_name = "a",
        },
    }
    function schedule:is_ready()
        return self.ready
    end
    function schedule:setup()
        self.ready = true
        return options.schedule_setup_result or result.ok(nil)
    end
    function schedule:start()
        return options.start_result or result.ok(nil)
    end
    function schedule:stop()
        return result.ok(nil)
    end
    function schedule:pause()
        return result.ok(nil)
    end
    function schedule:next()
        return options.next_result or result.ok(nil)
    end
    function schedule:previous()
        return options.previous_result or result.ok(nil)
    end
    function schedule:togglePauseResumeOrStartNow()
        return result.ok(nil)
    end
    function schedule:toggleStartStop()
        return result.ok(nil)
    end
    function schedule:selectPlaylist()
        return result.ok(nil)
    end
    function schedule:displayPlaylistSelectorUi()
        return result.ok(nil)
    end
    function schedule:displayMusicSelectorUi()
        return result.ok(nil)
    end
    function schedule:displayCurrentPlaylistMusicSelectorUi()
        return result.ok(nil)
    end
    function schedule:getStatus()
        return self.status_value
    end
    function schedule:get()
        return result.ok(self.status_value)
    end

    local progress = {}
    function progress:setup()
        return result.ok(nil)
    end
    function progress:refresh()
        refresh_count = refresh_count + 1
    end
    function progress:toggle()
        return result.ok(true)
    end
    function progress:show()
        return result.ok(nil)
    end
    function progress:hide()
        return result.ok(nil)
    end
    function progress:statusline()
        return "statusline"
    end

    _G.vim = {
        g = {},
        log = { levels = { INFO = 1, ERROR = 2 } },
        notify = function(message)
            table.insert(notifications, message)
        end,
        api = {
            nvim_create_augroup = function()
                return 1
            end,
            nvim_create_autocmd = function() end,
            nvim_list_uis = function()
                return { {} }
            end,
            nvim_create_user_command = function(name, callback)
                commands[name] = callback
            end,
        },
    }

    package.loaded["ambient.config"] = config
    package.loaded["ambient.schedule"] = schedule
    package.loaded["ambient.progress"] = progress
    t.clearModules("ambient.init")
    local ambient = require("ambient.init")
    return ambient,
        schedule,
        commands,
        notifications,
        function()
            return refresh_count
        end
end

t.test("init registers and routes AmbientPrevious", function()
    local ambient, schedule, commands = loadAmbient()
    ambient.register_commands()
    t.truthy(commands.AmbientPrevious)

    local calls = 0
    function schedule:previous()
        calls = calls + 1
        return result.ok(nil)
    end
    commands.AmbientPrevious()
    t.eq(calls, 1)
end)

t.test("init routes sorted and current-playlist music commands separately", function()
    local ambient, schedule, commands = loadAmbient()
    ambient.register_commands()
    t.truthy(commands.AmbientSelectMusic)
    t.truthy(commands.AmbientSelectCurrentPlaylistMusic)

    local sorted_calls = 0
    local current_calls = 0
    function schedule:displayMusicSelectorUi()
        sorted_calls = sorted_calls + 1
        return result.ok(nil)
    end
    function schedule:displayCurrentPlaylistMusicSelectorUi()
        current_calls = current_calls + 1
        return result.ok(nil)
    end
    commands.AmbientSelectMusic()
    commands.AmbientSelectCurrentPlaylistMusic()
    t.eq(sorted_calls, 1)
    t.eq(current_calls, 1)
end)

t.test("init forwards scheduler failures without re-wrapping them", function()
    local scheduler_error = result.err("PLAYER_ERROR")
    local ambient = loadAmbient({ previous_result = scheduler_error })
    local returned = ambient.previous()
    t.eq(returned, scheduler_error)
end)

t.test("ready orchestration is shared by next and previous and refreshes once", function()
    local ambient, _, _, _, refreshCount = loadAmbient({ schedule_ready = false })
    t.truthy(ambient.next().ok)
    t.truthy(ambient.previous().ok)
    t.eq(refreshCount(), 2)
end)

t.test("disabled config blocks start at the public boundary", function()
    local ambient = loadAmbient({
        config = {
            enable = false,
            show_notification = { disable_all = true },
        },
    })
    local started = ambient.start()
    t.falsy(started.ok)
    t.eq(started.err, "disabled")
end)
