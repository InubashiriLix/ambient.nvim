local t = require("tests.testlib")

local function deepcopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] ~= nil then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[deepcopy(key, seen)] = deepcopy(item, seen)
    end
    return copy
end

local function deepExtend(base, override)
    local merged = deepcopy(base)
    local function apply(target, source)
        for key, value in pairs(source or {}) do
            if type(value) == "table" and type(target[key]) == "table" then
                apply(target[key], value)
            else
                target[key] = deepcopy(value)
            end
        end
    end
    apply(merged, override)
    return merged
end

local function popupConfig(override)
    return deepExtend({
        enabled = true,
        duration_ms = 3000,
        position = "bottom_right",
        width = 46,
        height = 9,
        margin = {
            row = 1,
            col = 1,
        },
        border = "rounded",
        title = "Now Playing",
        cover = {
            enabled = true,
            width = 14,
            backend = "auto",
        },
        highlight = {
            normal = {},
            border = {},
            title = {},
            label = {},
            muted = {},
        },
    }, override or {})
end

local function loadPopup(options)
    options = options or {}
    local buffers = {}
    local windows = {}
    local timers = {}
    local next_buffer = 0
    local next_window = 0

    local bo = setmetatable({}, {
        __index = function(tbl, key)
            local value = {}
            rawset(tbl, key, value)
            return value
        end,
    })
    local wo = setmetatable({}, {
        __index = function(tbl, key)
            local value = {}
            rawset(tbl, key, value)
            return value
        end,
    })

    local uv = {
        fs_stat = function(path)
            if options.cover_path == path then
                return { size = 100 }
            end
            return nil
        end,
        new_timer = function()
            local timer = {
                closed = false,
                stopped = false,
            }
            function timer:start(timeout, repeat_ms, callback)
                self.timeout = timeout
                self.repeat_ms = repeat_ms
                self.callback = callback
            end
            function timer:stop()
                self.stopped = true
            end
            function timer:is_closing()
                return self.closed
            end
            function timer:close()
                self.closed = true
            end
            function timer:unref()
                self.unreferenced = true
            end
            table.insert(timers, timer)
            return timer
        end,
    }

    _G.vim = {
        uv = uv,
        o = {
            columns = options.columns or 100,
            lines = options.lines or 40,
            cmdheight = 1,
        },
        bo = bo,
        wo = wo,
        deepcopy = deepcopy,
        tbl_deep_extend = function(_, base, override)
            return deepExtend(base, override)
        end,
        tbl_extend = function(_, base, override)
            local value = deepcopy(base)
            for key, item in pairs(override or {}) do
                value[key] = item
            end
            return value
        end,
        schedule = function(callback)
            callback()
        end,
        schedule_wrap = function(callback)
            return callback
        end,
        fn = {
            executable = function()
                return 0
            end,
            strdisplaywidth = function(value)
                return #value
            end,
            strchars = function(value)
                return #value
            end,
            strcharpart = function(value, start, length)
                if length == nil then
                    return value:sub(start + 1)
                end
                return value:sub(start + 1, start + length)
            end,
        },
        api = {
            nvim_set_hl = function() end,
            nvim_create_namespace = function()
                return 1
            end,
            nvim_create_buf = function()
                next_buffer = next_buffer + 1
                buffers[next_buffer] = {
                    valid = true,
                    lines = {},
                }
                return next_buffer
            end,
            nvim_buf_is_valid = function(buffer)
                return buffers[buffer] ~= nil and buffers[buffer].valid
            end,
            nvim_open_win = function(buffer, _, config)
                next_window = next_window + 1
                windows[next_window] = {
                    valid = true,
                    buffer = buffer,
                    config = config,
                }
                return next_window
            end,
            nvim_win_is_valid = function(window)
                return windows[window] ~= nil and windows[window].valid
            end,
            nvim_win_close = function(window)
                windows[window].valid = false
            end,
            nvim_buf_delete = function(buffer)
                buffers[buffer].valid = false
            end,
            nvim_win_get_width = function(window)
                return windows[window].config.width
            end,
            nvim_win_get_height = function(window)
                return windows[window].config.height
            end,
            nvim_buf_set_lines = function(buffer, _, _, _, lines)
                buffers[buffer].lines = deepcopy(lines)
            end,
            nvim_buf_clear_namespace = function() end,
            nvim_buf_add_highlight = function() end,
        },
    }

    package.loaded.image = options.image
    t.clearModules("ambient.track_popup")
    local popup = require("ambient.track_popup")
    return popup, buffers, windows, timers
end

t.test("track popup opens in a corner and closes after its duration", function()
    local popup, buffers, windows, timers = loadPopup()
    local closed_reason

    t.truthy(popup:setup(popupConfig({
        width = 40,
        height = 8,
        position = "bottom_right",
        margin = { row = 2, col = 3 },
    })).ok)
    local shown = popup:show({
        name = "Night Drive",
        abs_path = "/music/night-drive.mp3",
        artist_name = "Ambient Unit",
        album_name = "Blue Hour",
    }, 1500, function(reason)
        closed_reason = reason
    end)

    t.truthy(shown.ok)
    t.truthy(popup:is_open())
    t.eq(windows[popup.window].config.row, 27)
    t.eq(windows[popup.window].config.col, 55)
    t.eq(timers[1].timeout, 1500)

    local rendered = table.concat(buffers[popup.buffer].lines, "\n")
    t.truthy(rendered:match("Night Drive"))
    t.truthy(rendered:match("Ambient Unit"))
    t.truthy(rendered:match("Blue Hour"))

    timers[1].callback()
    t.falsy(popup:is_open())
    t.eq(closed_reason, "timeout")
end)

t.test("track popup refreshes metadata without replacing its timer", function()
    local popup, _, _, timers = loadPopup()
    popup:setup(popupConfig())
    popup:show({
        name = "Track",
        abs_path = "/music/track.mp3",
    })
    local timer = timers[1]

    popup:update({
        name = "Track",
        abs_path = "/music/track.mp3",
        artist_name = { "One", "Two" },
        album_name = "Album",
    })
    t.truthy(popup:refresh().ok)
    t.eq(#timers, 1)
    t.eq(popup.timer, timer)

    timer.callback()
    t.falsy(popup:is_open())
end)

t.test("track popup uses image.nvim when it is available", function()
    local rendered = 0
    local cleared = 0
    local image_options
    local image_state = { images = {} }
    local image_api = {
        is_enabled = function()
            return true
        end,
        from_file = function(_, options)
            image_options = options
            local image = {
                id = options.id,
                global_state = image_state,
                render = function()
                    rendered = rendered + 1
                end,
                clear = function()
                    cleared = cleared + 1
                end,
            }
            image_state.images[image.id] = image
            return image
        end,
    }
    local popup, buffers = loadPopup({
        cover_path = "/tmp/cover.png",
        image = image_api,
    })
    popup:setup(popupConfig())
    popup:show({
        name = "Covered",
        cover_pic = {
            path = "/tmp/cover.png",
            mime = "image/png",
            source = "embedded",
            temporary = true,
        },
    })

    t.eq(rendered, 1)
    t.eq(image_options.x, 0)
    t.eq(image_options.y, 1)
    t.eq(image_options.max_width_window_percentage, 100)
    t.eq(image_options.max_height_window_percentage, 100)
    t.falsy(table.concat(buffers[popup.buffer].lines, "\n"):match("╭"))
    local image_id = image_options.id
    popup:close()
    t.eq(cleared, 1)
    t.eq(image_state.images[image_id], nil)
end)

t.test("track popup rejects invalid and disabled rendering requests", function()
    local popup = loadPopup()
    t.eq(popup:setup().err, popup.Error.INVALID_CONFIG)
    t.truthy(popup:update({ name = "Before setup" }).ok)
    t.eq(popup:render().err, popup.Error.NOT_READY)

    popup:setup(popupConfig({ enabled = false }))
    t.eq(popup:update({}).err, popup.Error.INVALID_ITEM)
    t.truthy(popup:update({ name = "Track" }).ok)
    t.eq(popup:render().err, popup.Error.DISABLED)
end)
