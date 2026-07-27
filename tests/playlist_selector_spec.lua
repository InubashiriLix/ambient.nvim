local t = require("tests.testlib")

local function playlist(path, count)
    local musics = {}
    for index = 1, count do
        musics[index] = { name = "track-" .. tostring(index) }
    end

    local item = {
        abs_path = path,
        name     = path:match("([^/]+)$"),
        musics   = musics,
    }
    function item:isEmpty()
        return #self.musics == 0
    end
    return item
end

local function loadSelector()
    t.clearModules("ambient.playlist_selector")
    local selector = require("ambient.playlist_selector")
    selector:reset()
    return selector
end

t.test("playlist selector exposes an ordered state snapshot", function()
    local selector = loadSelector()
    local empty    = playlist("/empty", 0)
    local first    = playlist("/first", 2)
    local second   = playlist("/second", 1)

    t.truthy(selector:add(empty).ok)
    t.truthy(selector:add(first).ok)
    t.truthy(selector:add(second).ok)
    t.truthy(selector:setup().ok)

    local snapshot = selector:snapshot()
    t.truthy(snapshot.ok)
    t.eq(snapshot.value.current_index, 2)
    t.eq(snapshot.value.playlists, { empty, first, second })
    t.eq(selector:current().value, first)

    snapshot.value.playlists[1] = nil
    t.eq(selector:snapshot().value.playlists, { empty, first, second })
end)

t.test("playlist selector changes the current non-empty playlist", function()
    local selector = loadSelector()
    local first    = playlist("/first", 1)
    local second   = playlist("/second", 1)
    selector:add(first)
    selector:add(second)
    selector:setup()

    t.truthy(selector:select(2).ok)
    t.eq(selector:current().value, second)
    t.eq(selector:snapshot().value.current_index, 2)
end)

t.test("playlist selector rejects invalid and empty selections", function()
    local selector = loadSelector()
    selector:add(playlist("/first", 1))
    selector:add(playlist("/empty", 0))
    selector:setup()

    t.eq(selector:select(0).err, "INVALID_INDEX")
    t.eq(selector:select(3).err, "INVALID_INDEX")
    t.eq(selector:select(1.5).err, "INVALID_INDEX")
    t.eq(selector:select(2).err, "EMPTY_PLAYLIST")
    t.eq(selector:snapshot().value.current_index, 1)
end)

t.test("playlist selector enforces setup and duplicate invariants", function()
    local selector = loadSelector()
    t.eq(selector:current().err, "INVALID_STATE")
    t.eq(selector:snapshot().err, "INVALID_STATE")
    t.eq(selector:setup().err, "NO_PLAYLISTS")

    selector:reset()
    t.truthy(selector:add(playlist("/one/library", 1)).ok)
    t.eq(selector:add(playlist("/two/library", 1)).err, "DUPLICATE_PLAYLIST")
    t.eq(selector:add(playlist("/", 1)).err, "INVALID_PATH")
    t.truthy(selector:setup().ok)
    t.eq(selector:add(playlist("/later", 1)).err, "INVALID_STATE")
end)
