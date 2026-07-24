local result = require("ambient.result")

local uv = vim.uv or vim.loop

---@alias AmbientTrackPopupPosition
---| "top_left"
---| "top_right"
---| "bottom_left"
---| "bottom_right"

---@alias AmbientTrackPopupCoverBackend
---| "auto"
---| "image.nvim"
---| "ascii"
---| "none"

---@class AmbientTrackPopupMarginConfig
---@field row integer
---@field col integer

---@class AmbientTrackPopupCoverConfig
---@field enabled boolean
---@field width integer
---@field backend AmbientTrackPopupCoverBackend

---@class AmbientTrackPopupHighlightConfig
---@field normal table
---@field border table
---@field title table
---@field label table
---@field muted table

---@class AmbientTrackPopupConfig
---@field enabled boolean
---@field duration_ms integer
---@field position AmbientTrackPopupPosition
---@field width integer
---@field height integer
---@field margin AmbientTrackPopupMarginConfig
---@field border string|string[]
---@field title string
---@field cover AmbientTrackPopupCoverConfig
---@field highlight AmbientTrackPopupHighlightConfig

---@class AmbientTrackPopupSnapshot
---@field name string
---@field abs_path? string
---@field artist_name? string|string[]
---@field album_name? string
---@field cover_pic? AmbientCoverPicture

---@enum AmbientPanelError
local Error = {
    NOT_READY            = "NOT_READY",
    INVALID_CONFIG       = "INVALID_CONFIG",
    INVALID_ITEM         = "INVALID_ITEM",
    DISABLED             = "DISABLED",
    SCREEN_TOO_SMALL     = "SCREEN_TOO_SMALL",
    WINDOW_CREATE_FAILED = "WINDOW_CREATE_FAILED",
}

---@enum AmbientPanelState
local State = {
    IDLE      = "IDLE",
    LOADING   = "LOADING",
    RENDERING = "RENDERING",
}

---@class AmbientTrackPopupPanel
---@field Error table<string, AmbientPanelError>
---@field State table<string, AmbientPanelState>
---@field state AmbientPanelState
---@field config? AmbientTrackPopupConfig
---@field current? AmbientTrackPopupSnapshot
---@field current_key? string
---@field buffer? integer
---@field window? integer
---@field timer? uv_timer_t
---@field image? table
---@field generation integer
---@field done_callback? fun(reason?: string)
local M = {
    Error      = Error,
    State      = State,
    state      = State.IDLE,
    generation = 0,
}

local highlight_namespace = nil

---@param value any
---@return string
local function sanitize(value)
    return (tostring(value or ""):gsub("[%c]", " "))
end

---@param value string
---@return integer
local function displayWidth(value)
    return vim.fn.strdisplaywidth(value)
end

---@param value string
---@param width integer
---@return string
local function trimToWidth(value, width)
    if width <= 0 then
        return ""
    end

    local text = sanitize(value)
    while displayWidth(text) > width do
        local chars = vim.fn.strchars(text)
        if chars <= 1 then
            return ""
        end
        text = vim.fn.strcharpart(text, 0, chars - 1)
    end
    return text
end

---@param value string
---@param width integer
---@return string
local function truncate(value, width)
    local text = sanitize(value)
    if displayWidth(text) <= width then
        return text
    end
    if width <= 1 then
        return trimToWidth(text, width)
    end
    return trimToWidth(text, width - 1) .. "…"
end

---@param value string
---@param width integer
---@return string
local function padRight(value, width)
    local text = trimToWidth(value, width)
    return text .. string.rep(" ", math.max(0, width - displayWidth(text)))
end

---@param artist string|string[]|nil
---@return string?
local function normalizeArtist(artist)
    if type(artist) == "table" then
        local names = {}
        for _, name in ipairs(artist) do
            if type(name) == "string" and name ~= "" then
                table.insert(names, sanitize(name))
            end
        end
        return #names > 0 and table.concat(names, ", ") or nil
    end

    if type(artist) == "string" and artist ~= "" then
        return sanitize(artist)
    end

    return nil
end

---@param path string?
---@return boolean
local function fileExists(path)
    return type(path) == "string"
        and path ~= ""
        and uv.fs_stat(path) ~= nil
end

---@return boolean
local function windowIsValid()
    return M.window ~= nil and vim.api.nvim_win_is_valid(M.window)
end

---@return boolean
local function bufferIsValid()
    return M.buffer ~= nil and vim.api.nvim_buf_is_valid(M.buffer)
end

local function closeTimer()
    if M.timer == nil then
        return
    end

    pcall(function()
        M.timer:stop()
        if not M.timer:is_closing() then
            M.timer:close()
        end
    end)
    M.timer = nil
end

local function clearImage()
    local image = M.image
    if image ~= nil and type(image.clear) == "function" then
        pcall(image.clear, image)
    end

    -- image.nvim keeps cleared images in its registry for reuse. Popup cover
    -- files are short-lived and every popup owns a different window, so
    -- retaining those entries would reuse stale window/path information.
    local image_state = image and image.global_state
    if image_state ~= nil
        and type(image_state.images) == "table"
        and image_state.images[image.id] == image
    then
        image_state.images[image.id] = nil
    end
    M.image = nil
end

---@param reason? string
local function closeWindow(reason)
    M.generation = M.generation + 1
    closeTimer()
    clearImage()

    if windowIsValid() then
        pcall(vim.api.nvim_win_close, M.window, true)
    end

    local callback  = M.done_callback
    M.window        = nil
    M.buffer        = nil
    M.done_callback = nil
    M.state         = M.State.IDLE

    if callback ~= nil then
        pcall(callback, reason)
    end
end

local function defineHighlights()
    local highlights = M.config.highlight
    pcall(vim.api.nvim_set_hl, 0, "AmbientTrackPopupNormal",
        vim.tbl_extend("force", { default = true }, highlights.normal))
    pcall(vim.api.nvim_set_hl, 0, "AmbientTrackPopupBorder",
        vim.tbl_extend("force", { default = true }, highlights.border))
    pcall(vim.api.nvim_set_hl, 0, "AmbientTrackPopupTitle",
        vim.tbl_extend("force", { default = true }, highlights.title))
    pcall(vim.api.nvim_set_hl, 0, "AmbientTrackPopupLabel",
        vim.tbl_extend("force", { default = true }, highlights.label))
    pcall(vim.api.nvim_set_hl, 0, "AmbientTrackPopupMuted",
        vim.tbl_extend("force", { default = true }, highlights.muted))
end

---@return integer, integer, integer, integer
local function windowGeometry()
    local max_width  = math.max(1, vim.o.columns - 4)
    local max_height = math.max(1, vim.o.lines - vim.o.cmdheight - 4)
    local width      = math.min(M.config.width, max_width)
    local height     = math.min(M.config.height, max_height)
    local margin     = M.config.margin
    local position   = M.config.position
    local max_row    = math.max(0, vim.o.lines - vim.o.cmdheight - height - 2)
    local max_col    = math.max(0, vim.o.columns - width - 2)

    local row = margin.row
    local col = margin.col
    if position == "bottom_left" or position == "bottom_right" then
        row = max_row - margin.row
    end
    if position == "top_right" or position == "bottom_right" then
        col = max_col - margin.col
    end

    return width, height,
        math.max(0, math.min(max_row, row)),
        math.max(0, math.min(max_col, col))
end

---@param width integer
---@param height integer
---@return string[]
local function placeholderCover(width, height)
    local lines = {}
    if width < 4 or height < 3 then
        for _ = 1, height do
            table.insert(lines, string.rep(" ", width))
        end
        return lines
    end

    local inner_width = width - 2
    local middle      = math.ceil(height / 2)
    for row = 1, height do
        if row == 1 then
            lines[row] = "╭" .. string.rep("─", inner_width) .. "╮"
        elseif row == height then
            lines[row] = "╰" .. string.rep("─", inner_width) .. "╯"
        else
            local content = ""
            if row == middle then
                content = "♪"
            elseif row == middle - 1 or row == middle + 1 then
                content = "·  ◉  ·"
            end
            local content_width = displayWidth(content)
            local left          = math.floor(math.max(0, inner_width - content_width) / 2)
            local right         = math.max(0, inner_width - content_width - left)
            lines[row]          = "│" .. string.rep(" ", left) .. content
                .. string.rep(" ", right) .. "│"
        end
    end
    return lines
end

---@param output string
---@param width integer
---@param height integer
---@return string[]
local function parseAsciiCover(output, width, height)
    local lines = {}
    output      = output:gsub("\27%[[%d;]*m", ""):gsub("\r", "")
    for line in (output .. "\n"):gmatch("(.-)\n") do
        if #lines >= height then
            break
        end
        table.insert(lines, padRight(line, width))
    end

    if #lines == 0 then
        return placeholderCover(width, height)
    end
    while #lines < height do
        table.insert(lines, string.rep(" ", width))
    end
    return lines
end

---@param lines string[]
---@param line integer
---@param col integer
---@param text string
local function writeAt(lines, line, col, text)
    if lines[line] == nil or col < 0 then
        return
    end

    local prefix       = vim.fn.strcharpart(lines[line], 0, col)
    local suffix_start = col + vim.fn.strchars(text)
    local suffix       = vim.fn.strcharpart(lines[line], suffix_start)
    lines[line]        = prefix .. text .. suffix
end

---@param cover_lines? string[]
local function drawBuffer(cover_lines)
    if not bufferIsValid() or M.current == nil then
        return
    end

    local width        = vim.api.nvim_win_get_width(M.window)
    local height       = vim.api.nvim_win_get_height(M.window)
    local show_cover   = M.config.cover.enabled == true
    local cover_width  = show_cover
        and math.min(M.config.cover.width, math.max(6, width - 22))
        or 0
    local gap          = show_cover and 2 or 0
    local metadata_col = cover_width + gap
    local value_width  = math.max(1, width - metadata_col - 1)
    local cover_height = math.max(1, height - 2)
    local lines        = {}

    for _ = 1, height do
        table.insert(lines, string.rep(" ", width))
    end

    if show_cover then
        cover_lines = cover_lines or placeholderCover(cover_width, cover_height)
        for row = 1, math.min(cover_height, #cover_lines) do
            writeAt(lines, row + 1, 0, padRight(cover_lines[row], cover_width))
        end
    end

    local artist = normalizeArtist(M.current.artist_name) or "Unknown artist"
    local album  = M.current.album_name and sanitize(M.current.album_name) or "Unknown album"
    local title  = truncate(M.current.name, value_width)

    writeAt(lines, 2, metadata_col, "NOW PLAYING")
    writeAt(lines, 3, metadata_col, padRight(title, value_width))
    if height >= 6 then
        writeAt(lines, 5, metadata_col, "󰠃  " .. truncate(artist, math.max(1, value_width - 3)))
        writeAt(lines, 6, metadata_col, "󰀥  " .. truncate(album, math.max(1, value_width - 3)))
    elseif height >= 5 then
        writeAt(lines, 4, metadata_col, truncate(artist, value_width))
        writeAt(lines, 5, metadata_col, truncate(album, value_width))
    end

    vim.bo[M.buffer].modifiable = true
    vim.api.nvim_buf_set_lines(M.buffer, 0, -1, false, lines)
    vim.bo[M.buffer].modifiable = false

    if highlight_namespace == nil then
        highlight_namespace = vim.api.nvim_create_namespace("ambient_track_popup")
    end
    vim.api.nvim_buf_clear_namespace(M.buffer, highlight_namespace, 0, -1)
    if show_cover then
        for row = 1, math.min(height - 1, cover_height + 1) do
            vim.api.nvim_buf_add_highlight(M.buffer, highlight_namespace,
                "AmbientTrackPopupMuted", row, 0, cover_width)
        end
    end
    vim.api.nvim_buf_add_highlight(M.buffer, highlight_namespace,
        "AmbientTrackPopupLabel", 1, metadata_col, -1)
    vim.api.nvim_buf_add_highlight(M.buffer, highlight_namespace,
        "AmbientTrackPopupTitle", 2, metadata_col, -1)
    if height >= 6 then
        vim.api.nvim_buf_add_highlight(M.buffer, highlight_namespace,
            "AmbientTrackPopupMuted", 4, metadata_col, -1)
        vim.api.nvim_buf_add_highlight(M.buffer, highlight_namespace,
            "AmbientTrackPopupMuted", 5, metadata_col, -1)
    end
end

---@return boolean
local function tryImageNvim()
    if M.current == nil
        or not M.config.cover.enabled
        or M.config.cover.backend == "ascii"
        or M.config.cover.backend == "none"
        or not fileExists(M.current.cover_pic and M.current.cover_pic.path)
    then
        return false
    end

    local ok, image_api = pcall(require, "image")
    if not ok
        or type(image_api.from_file) ~= "function"
        or (type(image_api.is_enabled) == "function" and not image_api.is_enabled())
    then
        return false
    end

    local height         = math.max(1, vim.api.nvim_win_get_height(M.window) - 2)
    local width          = math.min(M.config.cover.width,
        math.max(6, vim.api.nvim_win_get_width(M.window) - 22))
    local created, image = pcall(image_api.from_file, M.current.cover_pic.path, {
        id                           = "ambient-track-popup-cover-"
            .. tostring(M.generation),
        window                       = M.window,
        buffer                       = M.buffer,
        x                            = 0,
        y                            = 1,
        width                        = width,
        height                       = height,
        inline                       = false,
        namespace                    = "ambient.track_popup",
        max_width_window_percentage  = 100,
        max_height_window_percentage = 100,
    })
    if not created or image == nil or type(image.render) ~= "function" then
        return false
    end

    -- image.nvim may clone an already cached source image. Older versions copy
    -- the cached geometry limits instead of the new options, so enforce the
    -- popup-local geometry on the returned instance as well.
    image.window                       = M.window
    image.buffer                       = M.buffer
    image.inline                       = false
    image.max_width_window_percentage  = 100
    image.max_height_window_percentage = 100
    image.geometry                     = {
        x      = 0,
        y      = 1,
        width  = width,
        height = height,
    }

    -- Do not leave the character placeholder underneath a native image. A
    -- square cover can legitimately occupy fewer rows after aspect correction.
    drawBuffer({})
    local rendered = pcall(image.render, image)
    if not rendered then
        pcall(image.clear, image)
        drawBuffer()
        return false
    end

    M.image = image
    return true
end

local function renderCover()
    clearImage()
    drawBuffer()

    if M.current == nil
        or not M.config.cover.enabled
        or M.config.cover.backend == "none"
        or not fileExists(M.current.cover_pic and M.current.cover_pic.path)
    then
        return
    end

    if tryImageNvim() then
        return
    end

    if M.config.cover.backend == "image.nvim"
        or vim.system == nil
        or vim.fn.executable("img2txt") ~= 1
    then
        return
    end

    local generation = M.generation
    local width      = math.min(M.config.cover.width,
        math.max(6, vim.api.nvim_win_get_width(M.window) - 22))
    local height     = math.max(1, vim.api.nvim_win_get_height(M.window) - 2)
    local path       = M.current.cover_pic.path
    M.state          = M.State.LOADING

    local started = pcall(vim.system, {
        "img2txt",
        "--format=utf8",
        "--width=" .. tostring(width),
        "--height=" .. tostring(height),
        path,
    }, { text = true }, function(completed)
        vim.schedule(function()
            if generation ~= M.generation or not windowIsValid() then
                return
            end
            if completed.code == 0 and type(completed.stdout) == "string" then
                drawBuffer(parseAsciiCover(completed.stdout, width, height))
            end
            M.state = M.State.RENDERING
        end)
    end)

    if not started then
        M.state = M.State.RENDERING
    end
end

---@param duration_ms integer
local function startCloseTimer(duration_ms)
    closeTimer()
    if duration_ms <= 0 then
        return
    end

    local timer = uv.new_timer()
    if timer == nil then
        return
    end

    M.timer = timer
    timer:start(duration_ms, 0, vim.schedule_wrap(function()
        if M.timer == timer then
            closeWindow("timeout")
        end
    end))
    if timer.unref ~= nil then
        timer:unref()
    end
end

---@param config AmbientTrackPopupConfig Fully resolved configuration from ambient.config.
---@return AmbientResult<nil, AmbientPanelError>
function M:setup(config)
    if type(config) ~= "table" then
        return result.err(self.Error.INVALID_CONFIG)
    end

    closeWindow("setup")
    self.current     = nil
    self.current_key = nil
    self.config      = vim.deepcopy(config)
    defineHighlights()
    return result.ok(nil)
end

---@param new_item AmbientMusic|AmbientTrackPopupSnapshot
---@return AmbientResult<nil, AmbientPanelError>
function M:update(new_item)
    if type(new_item) ~= "table"
        or type(new_item.name) ~= "string"
        or new_item.name == ""
    then
        return result.err(self.Error.INVALID_ITEM)
    end

    self.current     = {
        name        = sanitize(new_item.name),
        abs_path    = new_item.abs_path,
        artist_name = vim.deepcopy(new_item.artist_name),
        album_name  = new_item.album_name and sanitize(new_item.album_name) or nil,
        cover_pic   = new_item.cover_pic and vim.deepcopy(new_item.cover_pic) or nil,
    }
    self.current_key = self.current.abs_path or self.current.name
    return result.ok(nil)
end

---@param detention_duration_ms? integer
---@param done_callback? fun(reason?: string)
---@return AmbientResult<nil, AmbientPanelError>
function M:render(detention_duration_ms, done_callback)
    if self.config == nil then
        return result.err(self.Error.NOT_READY)
    end
    if not self.config.enabled then
        return result.err(self.Error.DISABLED)
    end
    if self.current == nil then
        return result.err(self.Error.NOT_READY)
    end

    closeWindow("replaced")

    local width, height, row, col = windowGeometry()
    if width < 24 or height < 5 then
        return result.err(self.Error.SCREEN_TOO_SMALL)
    end

    local buffer             = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].bufhidden = "wipe"
    vim.bo[buffer].filetype  = "ambient_track_popup"

    local ok, window = pcall(vim.api.nvim_open_win, buffer, false, {
        relative  = "editor",
        style     = "minimal",
        focusable = false,
        noautocmd = true,
        width     = width,
        height    = height,
        row       = row,
        col       = col,
        border    = self.config.border,
        title     = self.config.title,
        title_pos = "center",
        zindex    = 80,
    })
    if not ok then
        pcall(vim.api.nvim_buf_delete, buffer, { force = true })
        return result.err(self.Error.WINDOW_CREATE_FAILED)
    end

    self.generation    = self.generation + 1
    self.buffer        = buffer
    self.window        = window
    self.done_callback = done_callback
    self.state         = self.State.RENDERING

    vim.wo[window].winhl      = table.concat({
        "Normal:AmbientTrackPopupNormal",
        "FloatBorder:AmbientTrackPopupBorder",
        "FloatTitle:AmbientTrackPopupTitle",
    }, ",")
    vim.wo[window].wrap       = false
    vim.wo[window].cursorline = false

    renderCover()
    startCloseTimer(detention_duration_ms or self.config.duration_ms)
    return result.ok(nil)
end

---@return AmbientResult<nil, AmbientPanelError>
function M:refresh()
    if not windowIsValid() or self.current == nil then
        return result.err(self.Error.NOT_READY)
    end

    self.generation = self.generation + 1
    self.state      = self.State.RENDERING
    renderCover()
    return result.ok(nil)
end

---@param item AmbientMusic|AmbientTrackPopupSnapshot
---@param duration_ms? integer
---@param done_callback? fun(reason?: string)
---@return AmbientResult<nil, AmbientPanelError>
function M:show(item, duration_ms, done_callback)
    local updated = self:update(item)
    if not updated.ok then
        return updated
    end
    return self:render(duration_ms, done_callback)
end

---@param reason? string
---@return AmbientResult<nil, nil>
function M:close(reason)
    closeWindow(reason or "closed")
    return result.ok(nil)
end

---@return boolean
function M:is_open()
    return windowIsValid()
end

---@return AmbientTrackPopupSnapshot?
function M:get_current()
    return self.current and vim.deepcopy(self.current) or nil
end

return M
