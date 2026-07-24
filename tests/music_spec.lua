local t = require("tests.testlib")

local function loadMusic()
    local deleted = {}
    _G.vim        = {
        uv = {
            fs_stat = function()
                return {
                    mtime     = { sec = 11 },
                    ctime     = { sec = 12 },
                    birthtime = { sec = 13 },
                }
            end,
        },
        fn = {
            delete = function(path)
                table.insert(deleted, path)
                return 0
            end,
        },
    }

    t.clearModules("ambient.music")
    return require("ambient.music"), deleted
end

t.test("music initializes optional metadata and cover fields", function()
    local music   = loadMusic()
    local created = music:new("test-music/ambient-test.wav")

    t.truthy(created.ok)
    t.eq(created.value.album_name, nil)
    t.eq(created.value.artist_name, nil)
    t.eq(created.value.cover_pic, nil)
end)

t.test("music releases its cover without changing persistent metadata", function()
    local music, deleted = loadMusic()
    local created        = music:new("test-music/ambient-test.wav")
    local item           = created.value

    item.album_name  = "Ambient Album"
    item.artist_name = { "Artist One", "Artist Two" }
    item.cover_pic   = {
        path      = "/tmp/ambient-cover.png",
        mime      = "image/png",
        width     = 200,
        height    = 200,
        source    = "embedded",
        temporary = true,
    }

    local released = item:releaseCoverPic()

    t.truthy(released.ok)
    t.eq(item.cover_pic, nil)
    t.eq(item.album_name, "Ambient Album")
    t.eq(item.artist_name, { "Artist One", "Artist Two" })
    t.eq(deleted, { "/tmp/ambient-cover.png" })

    local released_again = item:releaseCoverPic()
    t.truthy(released_again.ok)
    t.eq(item.cover_pic, nil)
end)
