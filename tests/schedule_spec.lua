local t      = require("tests.testlib")
local result = require("ambient.common.result")

local function makePlaylist(path, names, sort_field)
    local musics = {}
    for _, name in ipairs(names) do
        table.insert(musics, { name = name, abs_path = path .. "/" .. name .. ".wav" })
    end

    local item = {
        abs_path       = path,
        name           = path:match("([^/]+)$"),
        musics         = musics,
        sorted_indices = {},
        cursor         = 1,
        sort_field     = sort_field or "name",
        sort_direction = "asc",
    }
    for index = 1, #musics do
        item.sorted_indices[index] = index
    end

    function item:isEmpty()
        return #self.musics == 0
    end
    function item:getCurrent()
        return self.musics[self.sorted_indices[self.cursor]]
    end
    function item:hasNext()
        return self.cursor < #self.sorted_indices
    end
    function item:next()
        if not self:hasNext() then
            return nil
        end
        self.cursor = self.cursor + 1
        return self:getCurrent()
    end
    function item:hasPrev()
        return self.cursor > 1
    end
    function item:prev()
        if not self:hasPrev() then
            return nil
        end
        self.cursor = self.cursor - 1
        return self:getCurrent()
    end
    function item:reset()
        self.cursor = 1
    end
    function item:sort()
        self.sorted_indices = {}
        if self.sort_field == "name" and self.sort_direction == "desc" then
            for index = #self.musics, 1, -1 do
                table.insert(self.sorted_indices, index)
            end
        else
            for index = 1, #self.musics do
                table.insert(self.sorted_indices, index)
            end
        end
        self.cursor = 1
    end
    function item:setSortMethod(field, direction)
        self.sort_field     = field
        self.sort_direction = direction
        self:sort()
    end
    function item:setCursor(cursor)
        if self.sorted_indices[cursor] == nil then
            return result.err("INVALID_ARGUMENT")
        end
        self.cursor = cursor
        return result.ok(nil)
    end
    return item
end

local function loadSchedule(options)
    options         = options or {}
    local playlists = {}
    for path, names in pairs(options.playlists or { ["/one"] = { "a", "b", "c" } }) do
        playlists[path] = makePlaylist(path, names, options.sort_field)
    end

    local selector = {
        state         = "NOT_READY",
        items         = {},
        current_index = nil,
    }
    function selector:reset()
        self.state, self.items, self.current_index = "NOT_READY", {}, nil
    end
    function selector:add(item)
        table.insert(self.items, item)
        return result.ok(nil)
    end
    function selector:setup()
        if #self.items == 0 then
            return result.err("NO_PLAYLISTS")
        end
        self.state, self.current_index = "READY", 1
        return result.ok(nil)
    end
    function selector:select(index)
        if self.items[index] == nil then
            return result.err("INVALID_INDEX")
        end
        self.current_index = index
        return result.ok(nil)
    end
    function selector:current()
        local item = self.items[self.current_index]
        if item == nil then
            return result.err("NO_CURRENT_PLAYLIST")
        end
        return result.ok(item)
    end
    function selector:snapshot()
        local items = {}
        for index, item in ipairs(self.items) do
            items[index] = item
        end
        return result.ok({
            playlists     = items,
            current_index = self.current_index,
        })
    end

    local player = {
        played     = {},
        events     = {},
        play_error = options.play_error,
        progress   = options.progress,
    }
    function player:setup(config)
        self.config = config
    end
    function player:shutdown()
        self.shutdown_count = (self.shutdown_count or 0) + 1
    end
    function player:play(track)
        if self.play_error ~= nil then
            return self.play_error
        end
        table.insert(self.played, track.name)
        return nil
    end
    function player:pause()
        return self.pause_error
    end
    function player:resume()
        return self.resume_error
    end
    function player:drainEvents()
        local events = self.events
        self.events  = {}
        return events
    end
    function player:getProgress()
        return self.progress
    end

    local timers      = {}
    local user_events = {}
    local now         = 1000
    local uv          = {
        hrtime    = function()
            return 10
        end,
        now       = function()
            return now
        end,
        new_timer = function()
            if options.timer_failure then
                return nil
            end
            local timer = { closing = false, stopped = false }
            function timer:start(timeout, repeat_ms, callback)
                self.timeout, self.repeat_ms, self.callback = timeout, repeat_ms, callback
            end
            function timer:stop()
                self.stopped = true
            end
            function timer:is_closing()
                return self.closing
            end
            function timer:close()
                self.closing = true
            end
            table.insert(timers, timer)
            return timer
        end,
    }

    _G.vim = {
        uv            = uv,
        schedule      = function(fn)
            fn()
        end,
        schedule_wrap = function(fn)
            return fn
        end,
        api           = {
            nvim_exec_autocmds = function(event, opts)
                if event == "User" then
                    table.insert(user_events, opts.pattern)
                end
            end,
        },
    }

    package.loaded["ambient.models.playlist"]   = {
        SortField     = {
            name        = "name",
            modify_time = "modify_time",
            create_time = "create_time",
            random      = "random",
        },
        SortDirection = {
            asc  = "asc",
            desc = "desc",
        },
        new           = function(_, path)
            local item = playlists[path]
            if item == nil then
                return result.err("PATH_NOT_EXIST")
            end
            return result.ok(item)
        end,
    }
    package.loaded["ambient.playlist_selector"] = selector
    package.loaded["ambient.player"]            = player
    t.clearModules("ambient.schedule")
    local schedule = require("ambient.schedule")

    local config_playlists = {}
    for path in pairs(playlists) do
        table.insert(config_playlists, {
            abs_path        = path,
            ext             = { "wav" },
            recursive_depth = 1,
            sort_field      = options.sort_field or "name",
            sort_direction  = "asc",
        })
    end
    table.sort(config_playlists, function(a, b)
        return a.abs_path < b.abs_path
    end)

    local config = {
        playlists = config_playlists,
        mode      = options.mode or "without_interval_sequential",
        interval  = options.interval or { min_ms = 2000, max_ms = 2000 },
        volume    = 50,
    }
    return schedule, player, selector, timers, config, function(value)
        now = value
    end, user_events
end

t.test("schedule emits a dedicated event whenever a track starts", function()
    local schedule, _, _, _, config, _, events = loadSchedule()
    t.truthy(schedule:setup(config).ok)
    for index = #events, 1, -1 do
        table.remove(events, index)
    end

    t.truthy(schedule:start().ok)
    t.eq(events, {
        "AmbientStateChanged",
        "AmbientTrackChanged",
    })
end)

t.test("schedule traverses the selected playlist cursor in both directions", function()
    local schedule, player, _, _, config = loadSchedule()
    t.truthy(schedule:setup(config).ok)
    t.truthy(schedule:start().ok)
    t.truthy(schedule:next().ok)
    t.truthy(schedule:next().ok)
    t.eq(player.played, { "a", "b", "c" })

    t.truthy(schedule:previous().ok)
    t.truthy(schedule:previous().ok)
    t.eq(player.played, { "a", "b", "c", "b", "a" })

    t.truthy(schedule:next().ok)
    t.truthy(schedule:next().ok)
    t.eq(player.played, { "a", "b", "c", "b", "a", "b", "c" })
    t.eq(schedule.history, nil)
    t.eq(schedule.future, nil)
end)

t.test("previous at the beginning of the playlist is non-destructive", function()
    local schedule, _, _, _, config = loadSchedule()
    schedule:setup(config)
    schedule:start()
    local event_timer = schedule.event_timer

    local previous = schedule:previous()
    t.falsy(previous.ok)
    t.eq(previous.err, schedule.Error.NO_PREVIOUS_MUSIC)
    t.eq(schedule.state, schedule.State.PLAYING)
    t.eq(schedule.event_timer, event_timer)
    t.falsy(event_timer.stopped)
end)

t.test("next wraps a sequential playlist without creating navigation history", function()
    local schedule, player, selector, _, config = loadSchedule()
    schedule:setup(config)
    schedule:start()
    schedule:next()
    schedule:next()

    t.truthy(schedule:next().ok)
    t.eq(player.played, { "a", "b", "c", "a" })
    t.eq(selector:current().value.cursor, 1)
end)

t.test("schedule maps the player's direct error once at its boundary", function()
    local schedule, _, _, _, config = loadSchedule({ play_error = "MPV_START_FAILED" })
    schedule:setup(config)
    local started = schedule:start()

    t.falsy(started.ok)
    t.eq(started.err, schedule.Error.PLAYER_ERROR)
    t.eq(schedule:getStatus().last_error, "MPV_START_FAILED")
    t.eq(schedule.state, schedule.State.ERROR)
end)

t.test("continuous EOF immediately advances to the next track", function()
    local schedule, player, _, _, config = loadSchedule({ mode = "continuous" })
    schedule:setup(config)
    schedule:start()
    player.events = { { event = "end-file", reason = "eof" } }
    schedule.event_timer.callback()

    t.eq(player.played, { "a", "b" })
    t.eq(schedule:getStatus().current_music_name, "b")
    t.eq(schedule.state, schedule.State.PLAYING)
end)

t.test("interval EOF waits and then advances", function()
    local schedule, player, _, _, config, setNow = loadSchedule({
        mode     = "interval_sequential",
        interval = { min_ms = 2000, max_ms = 2000 },
    })
    schedule:setup(config)
    schedule:start()
    player.events = { { event = "end-file", reason = "eof" } }
    schedule.event_timer.callback()

    t.eq(schedule.state, schedule.State.INTERVAL)
    t.eq(schedule:getStatus().next_due_in_ms, 2000)
    setNow(1500)
    t.eq(schedule:getStatus().next_due_in_ms, 1500)
    schedule.interval_timer.callback()
    t.eq(player.played, { "a", "b" })
    t.eq(schedule.state, schedule.State.PLAYING)
end)

t.test("playlist changes reset the current playlist position", function()
    local schedule, player, _, _, config = loadSchedule({
        playlists = { ["/one"] = { "a", "b" }, ["/two"] = { "x", "y" } },
    })
    schedule:setup(config)
    schedule:start()
    schedule:next()
    t.truthy(schedule:selectPlaylist(2).ok)

    local previous = schedule:previous()
    t.eq(previous.err, schedule.Error.NO_PREVIOUS_MUSIC)
    t.truthy(schedule:start().ok)
    t.eq(player.played, { "a", "b", "x" })
end)

t.test("schedule skips unavailable playlists when another playlist is usable", function()
    local schedule, _, _, _, config = loadSchedule()
    table.insert(config.playlists, {
        abs_path        = "/missing",
        ext             = { "wav" },
        recursive_depth = 1,
        sort_field      = "name",
        sort_direction  = "asc",
    })

    local configured = schedule:setup(config)

    t.truthy(configured.ok)
    t.eq(schedule:getStatus().playlist_count, 1)
    t.eq(schedule:getStatus().playlist_warnings, {
        {
            path  = "/missing",
            error = "PATH_NOT_EXIST",
        },
    })
    t.eq(schedule.state, schedule.State.READY)
end)

t.test("schedule reports every unavailable playlist when none can be loaded", function()
    local schedule, _, _, _, config = loadSchedule()
    config.playlists                = {
        {
            abs_path        = "/missing",
            ext             = { "wav" },
            recursive_depth = 1,
            sort_field      = "name",
            sort_direction  = "asc",
        },
    }

    local configured = schedule:setup(config)

    t.falsy(configured.ok)
    t.eq(configured.err, schedule.Error.PLAYLIST_CONFIG_ERROR)
    t.eq(schedule:get_error_message(), "/missing: PATH_NOT_EXIST")
end)

t.test("playlist selection atomically applies its playback sorting method", function()
    local schedule, player, selector, _, config = loadSchedule({
        playlists = {
            ["/one"] = { "a", "b" },
            ["/two"] = { "x", "y" },
        },
    })
    schedule:setup(config)

    local selected = schedule:selectPlaylist(2, "name", "desc")

    t.truthy(selected.ok)
    local current = selector:current().value
    t.eq(current.name, "two")
    t.eq(current.sort_field, "name")
    t.eq(current.sort_direction, "desc")
    t.eq(current.sorted_indices, { 2, 1 })
    t.truthy(schedule:start().ok)
    t.eq(player.played, { "y" })
end)

t.test("invalid playlist sorting leaves the current playlist unchanged", function()
    local schedule, _, selector, _, config = loadSchedule({
        playlists = {
            ["/one"] = { "a" },
            ["/two"] = { "x" },
        },
    })
    schedule:setup(config)

    t.eq(schedule:selectPlaylist(2, "name", nil).err, "INVALID_SORT")
    t.eq(schedule:selectPlaylist(2, "invalid", "asc").err, "INVALID_SORT")
    t.eq(selector:current().value.name, "one")
end)

t.test("schedule rejects a stale playlist picker choice", function()
    local schedule, _, selector, _, config = loadSchedule({
        playlists = {
            ["/one"] = { "a" },
            ["/two"] = { "x" },
        },
    })
    schedule:setup(config)

    local stale = makePlaylist("/stale", { "z" })
    t.eq(schedule:selectPlaylist(2, "name", "asc", stale).err, "INVALID_INDEX")
    t.eq(selector:current().value.name, "one")
end)

t.test("schedule synchronously plays a selected source index", function()
    local schedule, player, selector, _, config = loadSchedule()
    schedule:setup(config)
    local current = selector:current().value

    local played = schedule:playSelectedMusic(current, 2)

    t.truthy(played.ok)
    t.eq(played.value, current.musics[2])
    t.eq(player.played, { "b" })
    t.eq(schedule:getStatus().current_music_name, "b")

    t.truthy(schedule:next().ok)
    t.truthy(schedule:previous().ok)
    t.eq(player.played, { "b", "c", "b" })
end)

t.test("schedule restores a saved playlist track from its beginning", function()
    local schedule, player, selector, _, config = loadSchedule()
    schedule:setup(config)

    local restored = schedule:restoreResumeState({
        playlist_path  = "/one",
        sort_field     = "name",
        sort_direction = "asc",
        track_path     = "/one/b.wav",
    })

    t.truthy(restored.ok)
    t.eq(player.played, { "b" })
    t.eq(selector:current().value.cursor, 2)
    t.eq(schedule.current_music.abs_path, "/one/b.wav")
end)

t.test("saved resume failures leave the active scheduler untouched", function()
    local schedule, player, selector, _, config = loadSchedule()
    schedule:setup(config)
    local original = selector:current().value

    local unavailable = schedule:restoreResumeState({
        playlist_path  = "/missing",
        sort_field     = "name",
        sort_direction = "asc",
        track_path     = "/missing/a.wav",
    })
    t.eq(unavailable.err, schedule.Error.SAVED_PLAYLIST_UNAVAILABLE)
    t.eq(selector:current().value, original)

    local deleted = schedule:restoreResumeState({
        playlist_path  = "/one",
        sort_field     = "name",
        sort_direction = "asc",
        track_path     = "/one/deleted.wav",
    })
    t.eq(deleted.err, schedule.Error.SAVED_TRACK_UNAVAILABLE)
    t.eq(selector:current().value, original)
    t.eq(player.played, {})
end)

t.test("ad-hoc playback does not replace the saved playlist resume target", function()
    local schedule, _, _, _, config = loadSchedule()
    schedule:setup(config)
    schedule:start()
    local ad_hoc = { name = "external", abs_path = "/external.wav" }
    t.truthy(schedule:playFile(ad_hoc).ok)

    t.eq(schedule:exportResumeState().err, schedule.Error.SAVED_TRACK_UNAVAILABLE)
end)

t.test("schedule rejects stale or invalid selected music", function()
    local schedule, player, selector, _, config = loadSchedule()
    schedule:setup(config)
    local current = selector:current().value

    t.eq(schedule:playSelectedMusic(makePlaylist("/stale", { "x" }), 1).err,
        "INVALID_INDEX")
    t.eq(schedule:playSelectedMusic(current, 99).err, "INVALID_INDEX")
    t.eq(player.played, {})
end)

t.test("status has a direct internal snapshot and a compatible public Result", function()
    local schedule, _, _, _, config = loadSchedule({
        progress = { time_ms = 250, duration_ms = 1000, percentage = 25 },
    })
    schedule:setup(config)
    schedule:start()
    schedule.current_music.artist_name = "Artist"
    schedule.current_music.album_name  = "Album"
    schedule.current_music.cover_pic   = {
        path      = "/tmp/cover.png",
        mime      = "image/png",
        width     = 100,
        height    = 100,
        source    = "embedded",
        temporary = true,
    }

    local status = schedule:getStatus()
    t.eq(status.current_music_name, "a")
    t.eq(status.current_artist_name, "Artist")
    t.eq(status.current_album_name, "Album")
    t.eq(status.current_cover_pic, schedule.current_music.cover_pic)
    t.eq(status.progress_percentage, 25)
    local wrapped = schedule:get()
    t.truthy(wrapped.ok)
    t.eq(wrapped.value.current_music_name, "a")
end)

t.test("playFile plays a track outside the playlist without moving the cursor", function()
    local schedule, player, selector, _, config = loadSchedule()
    schedule:setup(config)
    schedule:start()
    t.eq(player.played, { "a" })

    local external = { name = "external", abs_path = "/tmp/external.mp3" }
    local played   = schedule:playFile(external)

    t.truthy(played.ok)
    t.eq(player.played, { "a", "external" })
    t.eq(schedule:getStatus().current_music_name, "external")
    t.eq(schedule.state, schedule.State.PLAYING)

    t.truthy(schedule:next().ok)
    t.eq(player.played, { "a", "external", "b" })
    t.eq(selector:current().value.cursor, 2)
end)

t.test("playFile surfaces the player's error at the schedule boundary", function()
    local schedule, _, _, _, config = loadSchedule({ play_error = "MPV_START_FAILED" })
    schedule:setup(config)

    local external = { name = "external", abs_path = "/tmp/external.mp3" }
    local played   = schedule:playFile(external)

    t.falsy(played.ok)
    t.eq(played.err, schedule.Error.PLAYER_ERROR)
    t.eq(schedule.state, schedule.State.ERROR)
end)

t.test("timer allocation failure becomes a scheduler error", function()
    local schedule, _, _, _, config = loadSchedule({ timer_failure = true })
    schedule:setup(config)
    local started = schedule:start()
    t.eq(started.err, schedule.Error.TIMER_CREATE_FAILED)
    t.eq(schedule.state, schedule.State.ERROR)
end)
