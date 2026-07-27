local t      = require("tests.testlib")
local result = require("ambient.common.result")

local playlist_module = {
    SortField     = {
        name        = "name",
        create_time = "create_time",
        modify_time = "modify_time",
        random      = "random",
    },
    SortDirection = {
        asc  = "asc",
        desc = "desc",
    },
}

function playlist_module.getSortMethodTable()
    return {
        { field = "name",   direction = "asc" },
        { field = "name",   direction = "desc" },
        { field = "random", direction = "asc" },
    }
end

local function playlist(path, names)
    local musics         = {}
    local sorted_indices = {}
    for index, name in ipairs(names) do
        musics[index]         = {
            name     = name,
            abs_path = path .. "/" .. name .. ".wav",
        }
        sorted_indices[index] = index
    end

    local item = {
        abs_path       = path,
        name           = path:match("([^/]+)$"),
        musics         = musics,
        sorted_indices = sorted_indices,
        cursor         = 1,
        sort_field     = "name",
        sort_direction = "asc",
    }

    function item:isEmpty()
        return #self.musics == 0
    end

    function item:getSortMethod()
        return self.sort_field, self.sort_direction
    end

    function item:getSortedSnapshot(field, direction)
        if field == "invalid" then
            return result.err("INVALID_ARGUMENT")
        end

        local indices = {}
        for index = 1, #self.musics do
            indices[index] = index
        end
        if direction == "desc" then
            local reversed = {}
            for index = #indices, 1, -1 do
                table.insert(reversed, indices[index])
            end
            indices = reversed
        end

        local snapshot = {}
        for position, source_index in ipairs(indices) do
            snapshot[position] = {
                position     = position,
                source_index = source_index,
                music        = self.musics[source_index],
            }
        end
        return result.ok(snapshot)
    end

    return item
end

local function loadSelection(select_ui, options)
    options = options or {}

    local active    = options.active or playlist("/one", { "a", "b", "c" })
    local playlists = options.playlists or { active }
    local selector  = {}

    function selector:snapshot()
        return options.snapshot_result or result.ok({
            playlists     = playlists,
            current_index = options.current_index or 1,
        })
    end

    function selector:current()
        return options.current_result or result.ok(active)
    end

    local schedule = {
        current_music = options.current_music,
    }

    function schedule:selectPlaylist(index, field, direction, expected_playlist)
        self.selected_playlist = {
            index             = index,
            field             = field,
            direction         = direction,
            expected_playlist = expected_playlist,
        }
        return options.select_playlist_result or result.ok(nil)
    end

    function schedule:playSelectedMusic(selected_playlist, source_index)
        self.selected_music = {
            playlist     = selected_playlist,
            source_index = source_index,
        }
        return options.play_music_result
            or result.ok(selected_playlist.musics[source_index])
    end

    local progress = { refresh_count = 0 }
    function progress:refresh()
        self.refresh_count = self.refresh_count + 1
    end

    local notifications = {}
    local function notify(message, level)
        table.insert(notifications, {
            message = message,
            level   = level,
        })
    end

    _G.vim                                        = {
        ui  = { select = select_ui },
        log = { levels = { ERROR = 2 } },
    }
    package.loaded["ambient.models.playlist"]     = playlist_module
    package.loaded["ambient.playlist_selector"]   = selector
    package.loaded["ambient.schedule"]            = schedule
    package.loaded["ambient.components.progress"] = progress
    t.clearModules("ambient.selection")

    return require("ambient.selection"),
        schedule,
        progress,
        notifications,
        notify,
        active
end

t.test("selection applies playlist and sort in one readable workflow", function()
    local kinds                                                = {}
    local first                                                = playlist("/first", { "a" })
    local second                                               = playlist("/second", { "b" })
    local selection, schedule, progress, notifications, notify = loadSelection(
        function(items, opts, on_select)
            table.insert(kinds, opts.kind)
            on_select(items[2])
        end,
        {
            active    = first,
            playlists = { first, second },
        }
    )

    t.truthy(selection.select_playlist(notify).ok)
    t.eq(kinds, { "ambient_playlist_selector", "ambient_music_sort_selector" })
    t.eq(schedule.selected_playlist, {
        index             = 2,
        field             = "name",
        direction         = "desc",
        expected_playlist = second,
    })
    t.eq(second.sort_field, "name")
    t.eq(second.sort_direction, "asc")
    t.eq(progress.refresh_count, 1)
    t.eq(notifications[1].message, "Ambient playlist: second")
end)

t.test("selection cancellation stops the workflow without side effects", function()
    for cancel_stage = 1, 2 do
        local stage                                                = 0
        local selection, schedule, progress, notifications, notify = loadSelection(
            function(items, _, on_select)
                stage = stage + 1
                if stage == cancel_stage then
                    on_select(nil)
                    on_select(nil)
                else
                    on_select(items[1])
                end
            end
        )

        t.truthy(selection.select_playlist(notify).ok)
        t.eq(schedule.selected_playlist, nil)
        t.eq(progress.refresh_count, 0)
        t.eq(notifications, {})
    end
end)

t.test("selection resumes across genuinely asynchronous UI callbacks", function()
    local pending                                  = {}
    local selection, schedule, progress, _, notify = loadSelection(
        function(items, opts, on_select)
            table.insert(pending, {
                items     = items,
                kind      = opts.kind,
                on_select = on_select,
            })
        end
    )

    t.truthy(selection.select_playlist(notify).ok)
    t.eq(schedule.selected_playlist, nil)
    t.eq(pending[1].kind, "ambient_playlist_selector")

    pending[1].on_select(pending[1].items[1])
    t.eq(schedule.selected_playlist, nil)
    t.eq(pending[2].kind, "ambient_music_sort_selector")

    pending[2].on_select(pending[2].items[2])
    t.eq(schedule.selected_playlist.field, "name")
    t.eq(schedule.selected_playlist.direction, "desc")
    t.eq(progress.refresh_count, 1)
end)

t.test("sorted music selection does not mutate playback order", function()
    local kinds                                                        = {}
    local selection, schedule, progress, notifications, notify, active = loadSelection(
        function(items, opts, on_select)
            table.insert(kinds, opts.kind)
            if opts.kind == "ambient_music_sort_selector" then
                on_select(items[2])
            else
                on_select(items[1])
            end
        end
    )

    t.truthy(selection.select_music(notify).ok)
    t.eq(kinds, { "ambient_music_sort_selector", "ambient_music_selector" })
    t.eq(schedule.selected_music.source_index, 3)
    t.eq(active.sorted_indices, { 1, 2, 3 })
    t.eq(active.cursor, 1)
    t.eq(progress.refresh_count, 1)
    t.eq(notifications[1].message, "Ambient music: c")
end)

t.test("current playlist selection follows playback order and focuses playing music", function()
    local displayed_items
    local initial_index
    local snacks_index
    local active          = playlist("/one", { "a", "b", "c" })
    active.sorted_indices = { 3, 1, 2 }
    active.cursor         = 2

    local selection, schedule, progress, _, notify = loadSelection(
        function(items, opts, on_select)
            displayed_items = items
            initial_index   = opts.initial_index
            opts.snacks.on_show({
                list = {
                    view = function(_, index)
                        snacks_index = index
                    end,
                },
            })
            on_select(items[initial_index])
        end,
        {
            active        = active,
            current_music = active.musics[2],
        }
    )

    t.truthy(selection.select_current_playlist_music(notify).ok)
    t.eq(displayed_items[1].source_index, 3)
    t.eq(displayed_items[2].source_index, 1)
    t.eq(displayed_items[3].source_index, 2)
    t.eq(initial_index, 3)
    t.eq(snacks_index, 3)
    t.eq(schedule.selected_music.source_index, 2)
    t.eq(progress.refresh_count, 1)
end)

t.test("selection reports UI and schedule failures exactly once", function()
    local selection, _, progress, notifications, notify = loadSelection(function()
        error("broken selector")
    end)

    t.truthy(selection.select_music(notify).ok)
    t.eq(progress.refresh_count, 0)
    t.eq(#notifications, 1)
    t.truthy(notifications[1].message:match("UI_FAILED"))

    selection, _, progress, notifications, notify = loadSelection(
        function(items, _, on_select)
            on_select(items[1])
        end,
        {
            select_playlist_result = result.err("STALE_SELECTION"),
        }
    )

    t.truthy(selection.select_playlist(notify).ok)
    t.eq(progress.refresh_count, 0)
    t.eq(#notifications, 1)
    t.truthy(notifications[1].message:match("STALE_SELECTION"))
end)

t.test("selection returns state and input errors before opening UI", function()
    local opened                                 = false
    local selection, _, _, notifications, notify = loadSelection(
        function()
            opened = true
        end,
        {
            current_result = result.err("NO_CURRENT_PLAYLIST"),
        }
    )

    t.eq(selection.select_music(notify).err, "NO_CURRENT_PLAYLIST")
    t.eq(selection.select_playlist(nil).err, selection.Error.INVALID_INPUT)
    t.falsy(opened)
    t.eq(notifications, {})
end)
