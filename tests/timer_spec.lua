local t      = require("tests.testlib")
local result = require("ambient.common.result")

local scheduled = false
local fired     = false
local uv_callback

_G.vim = {
    uv = {
        new_timer = function()
            return {
                start = function(_, _, _, callback)
                    uv_callback = callback
                    return true
                end,
            }
        end,
    },
    schedule_wrap = function(callback)
        return function(...)
            scheduled = true
            return callback(...)
        end
    end,
}

package.loaded["ambient.common.timer"] = nil
local timer = require("ambient.common.timer")

t.test("timer callbacks run through the Neovim event loop", function()
    local created = timer.new(15, function()
        fired = true
    end)

    t.truthy(created.ok)
    t.eq(created.value:start(), result.ok(nil))
    t.falsy(scheduled)
    t.falsy(fired)

    uv_callback()

    t.truthy(scheduled)
    t.truthy(fired)
end)

