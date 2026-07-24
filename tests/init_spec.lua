local t = require("tests.testlib")
local result = require("ambient.result")

local function loadAmbient(options)
    options = options or {}
    local commands = {}
    local command_options = {}
    local notifications = {}
    local autocmds = {}
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
            playlist_warnings = options.playlist_warnings or {},
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
    function schedule:get_error_message()
        return options.schedule_last_error
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

    local display = {
        current_key = nil,
        shown = {},
        open = false,
        refresh_count = 0,
    }
    function display:setup(display_config)
        self.config = display_config
        return result.ok(nil)
    end
    function display:show(item, duration_ms)
        table.insert(self.shown, {
            item = item,
            duration_ms = duration_ms,
        })
        self.current_key = item.abs_path or item.name
        self.open = true
        return result.ok(nil)
    end
    function display:update(item)
        self.current_key = item.abs_path or item.name
        return result.ok(nil)
    end
    function display:refresh()
        self.refresh_count = self.refresh_count + 1
        return result.ok(nil)
    end
    function display:close()
        self.open = false
        return result.ok(nil)
    end
    function display:is_open()
        return self.open
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
            nvim_create_autocmd = function(event, autocmd)
                table.insert(autocmds, {
                    event = event,
                    value = autocmd,
                })
            end,
            nvim_list_uis = function()
                return { {} }
            end,
            nvim_create_user_command = function(name, callback, command_opts)
                commands[name] = callback
                command_options[name] = command_opts
            end,
        },
    }

    package.loaded["ambient.config"] = config
    package.loaded["ambient.schedule"] = schedule
    package.loaded["ambient.progress"] = progress
    package.loaded["ambient.track_popup"] = display
    t.clearModules("ambient.init")
    local ambient = require("ambient.init")
    return ambient,
        schedule,
        commands,
        notifications,
        function()
            return refresh_count
        end,
        command_options,
        display,
        autocmds
end

t.test("init replaces flat commands with the Ambient command tree", function()
    local ambient, schedule, commands = loadAmbient()
    ambient.register_commands()
    t.truthy(commands.Ambient)
    t.falsy(commands.AmbientPrevious)
    t.falsy(commands.AmbientSelectMusic)

    local calls = 0
    function schedule:previous()
        calls = calls + 1
        return result.ok(nil)
    end
    commands.Ambient({ args = "previous" })
    t.eq(calls, 1)
end)

t.test("track events show and refresh the popup", function()
    local ambient, schedule, _, _, _, _, display, autocmds = loadAmbient()
    t.truthy(ambient.setup().ok)

    local callbacks = {}
    for _, autocmd in ipairs(autocmds) do
        if autocmd.event == "User" and type(autocmd.value.pattern) == "string" then
            callbacks[autocmd.value.pattern] = autocmd.value.callback
        end
    end

    schedule.current_music = {
        name = "Night Drive",
        abs_path = "/music/night-drive.mp3",
    }
    callbacks.AmbientTrackChanged()
    t.eq(#display.shown, 1)

    schedule.current_music.artist_name = "Ambient Unit"
    callbacks.AmbientTrackInfoUpdated()
    t.eq(display.refresh_count, 1)

    schedule.current_music = nil
    callbacks.AmbientStateChanged()
    t.falsy(display.open)
end)

t.test("init routes sorted and current-playlist music commands separately", function()
    local ambient, schedule, commands = loadAmbient()
    ambient.register_commands()

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
    commands.Ambient({ args = "select music" })
    commands.Ambient({ args = "select current-playlist-music" })
    t.eq(sorted_calls, 1)
    t.eq(current_calls, 1)
end)

t.test("Ambient command completion follows the command tree", function()
    local ambient, _, commands, _, _, command_options = loadAmbient()
    ambient.register_commands()
    local complete = command_options.Ambient.complete

    t.eq(complete("", "Ambient ", 8), {
        "display",
        "next",
        "pause",
        "previous",
        "progress",
        "select",
        "start",
        "status",
        "stop",
        "toggle",
    })
    t.eq(complete("p", "Ambient p", 9), { "pause", "previous", "progress" })
    t.eq(complete("", "Ambient toggle ", 15), { "pause", "stop" })
    t.eq(complete("current", "Ambient select current", 22), { "current-playlist-music" })
    t.eq(complete("", "Ambient progress ", 17), { "toggle" })
    t.eq(complete("", "Ambient status ", 15), {})
    t.truthy(commands.Ambient)
end)

t.test("init can show the current track on demand", function()
    local ambient, schedule, _, _, _, _, display = loadAmbient()
    schedule.current_music = {
        name = "Night Drive",
        abs_path = "/music/night-drive.mp3",
    }

    local shown = ambient.show_current_track(1250)
    t.truthy(shown.ok)
    t.eq(display.shown[1], {
        item = schedule.current_music,
        duration_ms = 1250,
    })

    schedule.current_music = nil
    t.eq(ambient.show_current_track().err, "NO_CURRENT_MUSIC")
end)

t.test("Ambient command reports incomplete and unknown paths", function()
    local ambient, _, commands, notifications = loadAmbient({
        config = {
            enable = true,
            show_notification = { disable_all = false },
        },
    })
    ambient.register_commands()

    commands.Ambient({ args = "select" })
    commands.Ambient({ args = "does-not-exist" })

    t.truthy(notifications[1]:match("subcommand required"))
    t.truthy(notifications[1]:match("current%-playlist%-music, music, playlist"))
    t.truthy(notifications[2]:match("Unknown Ambient command"))
end)

t.test("init forwards scheduler failures without re-wrapping them", function()
    local scheduler_error = result.err("PLAYER_ERROR")
    local ambient = loadAmbient({ previous_result = scheduler_error })
    local returned = ambient.previous()
    t.eq(returned, scheduler_error)
end)

t.test("setup reports skipped playlists and detailed fatal playlist errors", function()
    local cfg = {
        enable = true,
        show_notification = {
            disable_all = false,
            when_finish_setup = false,
            when_show_total_music_count = false,
        },
    }
    local ambient, _, _, notifications = loadAmbient({
        config = cfg,
        playlist_warnings = {
            {
                path = "/missing",
                error = "PATH_NOT_EXIST",
            },
        },
    })

    t.truthy(ambient.setup(cfg).ok)
    t.truthy(notifications[1]:match("Skipped playlist /missing: PATH_NOT_EXIST"))

    ambient, _, _, notifications = loadAmbient({
        config = cfg,
        schedule_setup_result = result.err("PLAYLIST_CONFIG_ERROR"),
        schedule_last_error = "/missing: PATH_NOT_EXIST",
    })

    local configured = ambient.setup(cfg)
    t.falsy(configured.ok)
    t.truthy(notifications[1]:match("PLAYLIST_CONFIG_ERROR"))
    t.truthy(notifications[1]:match("/missing: PATH_NOT_EXIST"))
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
