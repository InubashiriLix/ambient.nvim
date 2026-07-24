package.path = table.concat({
    "./lua/?.lua",
    "./lua/?/init.lua",
    "./tests/?.lua",
    "./?/init.lua",
    package.path,
}, ";")

require("tests.player_spec")
require("tests.music_spec")
require("tests.mpv_ipc_spec")
require("tests.track_popup_spec")
require("tests.playlist_selector_spec")
require("tests.schedule_spec")
require("tests.init_spec")
require("tests.testlib").run()
