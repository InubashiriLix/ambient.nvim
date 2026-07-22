package.path = table.concat({
    "./lua/?.lua",
    "./lua/?/init.lua",
    "./tests/?.lua",
    "./?/init.lua",
    package.path,
}, ";")

require("tests.player_spec")
require("tests.schedule_spec")
require("tests.init_spec")
require("tests.testlib").run()
