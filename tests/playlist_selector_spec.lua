local t = require("tests.testlib")
local result = require("ambient.result")

local playlist_module = {
    SortField = {
        name = "name",
        create_time = "create_time",
        modify_time = "modify_time",
        random = "random",
    },
    SortDirection = {
        asc = "asc",
        desc = "desc",
    },
}

function playlist_module.getSortMethodTable()
    return {
        { field = playlist_module.SortField.name, direction = playlist_module.SortDirection.desc },
    }
end

local function makePlaylist(path, names)
    local musics = {}
    local sorted_indices = {}
    for index, name in ipairs(names) do
        musics[index] = { name = name, abs_path = path .. "/" .. name .. ".wav" }
        sorted_indices[index] = index
    end

    local item = {
        abs_path = path,
        name = path:match("([^/]+)$"),
        musics = musics,
        sorted_indices = sorted_indices,
        cursor = 1,
    }

    function item:isEmpty()
        return #self.musics == 0
    end

    function item:getSortMethod()
        return playlist_module.SortField.name, playlist_module.SortDirection.asc
    end

    function item:getSortedSnapshot()
        local snapshot = {}
        for source_index = #self.musics, 1, -1 do
            table.insert(snapshot, {
                position = #snapshot + 1,
                source_index = source_index,
                music = self.musics[source_index],
            })
        end
        return result.ok(snapshot)
    end

    function item:setCursor(cursor)
        self.cursor = cursor
        return result.ok(nil)
    end

    return item
end

local function loadSelector(select_ui)
    _G.vim = { ui = { select = select_ui } }
    package.loaded["ambient.playlist"] = playlist_module
    t.clearModules("ambient.playlist_selector")
    return require("ambient.playlist_selector")
end

t.test("sorted music selector prompts for sorting before music", function()
    local prompts = {}
    local selector = loadSelector(function(items, opts, on_select)
        table.insert(prompts, opts.kind)
        on_select(items[1])
    end)

    local current = makePlaylist("/current", { "a", "b" })
    selector:reset()
    t.truthy(selector:addPlayList(current).ok)
    t.truthy(selector:setup().ok)

    local selected_music
    local displayed = selector:displayMusicItemSelectUi(function(selected)
        t.truthy(selected.ok)
        selected_music = selected.value
    end)

    t.truthy(displayed.ok)
    t.eq(prompts, { "ambient_music_sort_selector", "ambient_music_selector" })
    t.eq(selected_music, current.musics[2])
    t.eq(current.cursor, 2)
end)

t.test("current playlist selector preserves order and moves the initial cursor", function()
    local prompts = {}
    local displayed_items
    local initial_index
    local snacks_cursor
    local selector = loadSelector(function(items, opts, on_select)
        table.insert(prompts, opts.kind)
        displayed_items = items
        initial_index = opts.initial_index
        opts.snacks.on_show({
            list = {
                view = function(_, index)
                    snacks_cursor = index
                end,
            },
        })
        on_select(items[initial_index])
    end)

    local registered = makePlaylist("/registered", { "registered" })
    local current = makePlaylist("/current", { "a", "b", "c" })
    current.cursor = 2
    selector:reset()
    selector:addPlayList(registered)
    selector:setup()

    local selected_music
    local displayed = selector:displayCurrentPlayListMusicItemSelectUi(current, function(selected)
        t.truthy(selected.ok)
        selected_music = selected.value
    end)

    t.truthy(displayed.ok)
    t.eq(prompts, { "ambient_current_playlist_music_selector" })
    t.eq(displayed_items[1].music, current.musics[1])
    t.eq(displayed_items[2].music, current.musics[2])
    t.eq(displayed_items[3].music, current.musics[3])
    t.eq(initial_index, 2)
    t.eq(snacks_cursor, 2)
    t.eq(selected_music, current.musics[2])
    t.eq(current.cursor, 2)
    t.eq(registered.cursor, 1)
end)

t.test("current playlist selector focuses the playing track before the next cursor", function()
    local initial_index
    local selector = loadSelector(function(items, opts, on_select)
        initial_index = opts.initial_index
        on_select(nil)
    end)
    local current = makePlaylist("/current", { "a", "b", "c" })
    current.cursor = 2
    selector:reset()
    selector:addPlayList(current)
    selector:setup()

    local displayed = selector:displayCurrentPlayListMusicItemSelectUi(
        current,
        nil,
        current.musics[1]
    )

    t.truthy(displayed.ok)
    t.eq(initial_index, 1)
end)

t.test("current playlist music selector rejects an empty playlist before opening UI", function()
    local ui_opened = false
    local selector = loadSelector(function()
        ui_opened = true
    end)
    local registered = makePlaylist("/registered", { "registered" })
    selector:reset()
    selector:addPlayList(registered)
    selector:setup()

    local displayed = selector:displayCurrentPlayListMusicItemSelectUi(makePlaylist("/empty", {}))
    t.falsy(displayed.ok)
    t.eq(displayed.err, "EMPTY_PLAYLIST")
    t.falsy(ui_opened)
end)
