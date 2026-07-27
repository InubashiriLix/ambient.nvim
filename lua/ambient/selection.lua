local result          = require("ambient.result")
local playlist_module = require("ambient.playlist")
local selector        = require("ambient.playlist_selector")
---@type AmbientSchedule
local schedule        = require("ambient.schedule")
local progress        = require("ambient.progress")

local M = {}

---@enum AmbientSelectionError
M.Error = {
    CANCELLED         = "CANCELLED",
    INVALID_INPUT     = "INVALID_INPUT",
    INVALID_SELECTION = "INVALID_SELECTION",
    INVALID_SORT      = "INVALID_SORT",
    NO_PLAYLISTS      = "NO_PLAYLISTS",
    EMPTY_PLAYLIST    = "EMPTY_PLAYLIST",
    UI_FAILED         = "UI_FAILED",
}

---@type table<SortField, string>
local sort_field_labels = {
    [playlist_module.SortField.name]        = "Name",
    [playlist_module.SortField.create_time] = "Created",
    [playlist_module.SortField.modify_time] = "Modified",
    [playlist_module.SortField.random]      = "Random",
}

---@type table<SortDirection, string>
local sort_direction_labels = {
    [playlist_module.SortDirection.asc]  = "ascending",
    [playlist_module.SortDirection.desc] = "descending",
}

---@class AmbientSelectionRequest
---@field items table
---@field opts table

---This is the only place where vim.ui.select's callback enters our code.
---Selection workflows yield a request here and resume as ordinary, linear code.
---@param items table
---@param opts table
---@return any? choice
---@return any? error
local function awaitSelect(items, opts)
    return coroutine.yield({
        items = items,
        opts  = opts,
    })
end

---@param notify fun(message: string, level?: integer)
---@param error_value any
local function reportError(notify, error_value)
    notify("Ambient error: " .. tostring(error_value), vim.log.levels.ERROR)
end

---Drive one selection workflow. Public selection functions report that the UI
---was opened; completion happens later when vim.ui.select invokes its callback.
---@param workflow fun(): AmbientResult<nil, any>
---@param notify fun(message: string, level?: integer)
---@return AmbientResult<nil, nil>
local function run(workflow, notify)
    local thread   = coroutine.create(workflow)
    local finished = false

    local resume
    resume = function(choice, select_error)
        if finished then
            return
        end

        local resumed, yielded = coroutine.resume(thread, choice, select_error)
        if not resumed then
            finished = true
            reportError(notify, M.Error.UI_FAILED .. ": " .. tostring(yielded))
            return
        end

        if coroutine.status(thread) == "dead" then
            finished = true
            if not yielded.ok and yielded.err ~= M.Error.CANCELLED then
                reportError(notify, yielded.err)
            end
            return
        end

        ---@cast yielded AmbientSelectionRequest
        if type(yielded) ~= "table"
            or type(yielded.items) ~= "table"
            or type(yielded.opts) ~= "table" then
            resume(nil, M.Error.UI_FAILED)
            return
        end

        local opened, open_error = pcall(
            vim.ui.select,
            yielded.items,
            yielded.opts,
            function(selected)
                resume(selected, nil)
            end
        )
        if not opened then
            resume(nil, M.Error.UI_FAILED .. ": " .. tostring(open_error))
        end
    end

    resume(nil, nil)
    return result.ok(nil)
end

---@param item { field: SortField, direction: SortDirection }
---@param current_field? SortField
---@param current_direction? SortDirection
---@return string
local function formatSort(item, current_field, current_direction)
    local is_current = item.field == current_field
        and (item.field == playlist_module.SortField.random
            or item.direction == current_direction)

    local label = sort_field_labels[item.field]
    if item.field ~= playlist_module.SortField.random then
        label = string.format("%s %s", label, sort_direction_labels[item.direction])
    end

    return string.format("%s %s", label, is_current and "(current mode)" or " ")
end

---@param notify? fun(message: string, level?: integer)
---@return AmbientResult<nil, any>
function M.select_playlist(notify)
    if type(notify) ~= "function" then
        return result.err(M.Error.INVALID_INPUT)
    end

    local snapshot = selector:snapshot()
    if not snapshot.ok then
        return result.err(snapshot.err)
    end
    if #snapshot.value.playlists == 0 then
        return result.err(M.Error.NO_PLAYLISTS)
    end

    local items = {}
    for index, item in ipairs(snapshot.value.playlists) do
        items[index] = {
            index    = index,
            playlist = item,
        }
    end

    return run(function()
        local choice, select_error = awaitSelect(items, {
            prompt      = "Select a playlist",
            kind        = "ambient_playlist_selector",
            format_item = function(item)
                local marker = item.index == snapshot.value.current_index and ">" or " "
                return string.format(
                    "%s %s (%d tracks)",
                    marker,
                    item.playlist.name,
                    #item.playlist.musics
                )
            end,
        })
        if select_error ~= nil then
            return result.err(select_error)
        end
        if choice == nil then
            return result.err(M.Error.CANCELLED)
        end
        if choice.playlist:isEmpty() then
            return result.err(M.Error.EMPTY_PLAYLIST)
        end

        local current_field, current_direction = choice.playlist:getSortMethod()
        local sort_choice, sort_error = awaitSelect(playlist_module.getSortMethodTable(), {
            prompt      = "Select Sort Method",
            kind        = "ambient_music_sort_selector",
            format_item = function(item)
                return formatSort(item, current_field, current_direction)
            end,
        })
        if sort_error ~= nil then
            return result.err(sort_error)
        end
        if sort_choice == nil then
            return result.err(M.Error.CANCELLED)
        end

        -- Passing the playlist object prevents an old UI from selecting the
        -- wrong index after the playlist collection has been rebuilt.
        local selected = schedule:selectPlaylist(
            choice.index,
            sort_choice.field,
            sort_choice.direction,
            choice.playlist
        )
        if not selected.ok then
            return result.err(selected.err)
        end

        progress:refresh()
        notify("Ambient playlist: " .. choice.playlist.name)
        return result.ok(nil)
    end, notify)
end

---@param notify? fun(message: string, level?: integer)
---@return AmbientResult<nil, any>
function M.select_music(notify)
    if type(notify) ~= "function" then
        return result.err(M.Error.INVALID_INPUT)
    end

    local current = selector:current()
    if not current.ok then
        return result.err(current.err)
    end

    local active_playlist = current.value
    ---@cast active_playlist AmbientPlayList
    if active_playlist:isEmpty() then
        return result.err(M.Error.EMPTY_PLAYLIST)
    end

    return run(function()
        local current_field, current_direction = active_playlist:getSortMethod()
        local sort_choice, sort_error = awaitSelect(playlist_module.getSortMethodTable(), {
            prompt      = "Sort music",
            kind        = "ambient_music_sort_selector",
            format_item = function(item)
                return formatSort(item, current_field, current_direction)
            end,
        })
        if sort_error ~= nil then
            return result.err(sort_error)
        end
        if sort_choice == nil then
            return result.err(M.Error.CANCELLED)
        end

        -- This snapshot controls display order only. It deliberately does not
        -- change the playlist's playback order.
        local sorted = active_playlist:getSortedSnapshot(
            sort_choice.field,
            sort_choice.direction
        )
        if not sorted.ok then
            return result.err(M.Error.INVALID_SORT)
        end

        local music_choice, music_error = awaitSelect(sorted.value, {
            prompt      = "Select music",
            kind        = "ambient_music_selector",
            format_item = function(item)
                return item.music.name
            end,
        })
        if music_error ~= nil then
            return result.err(music_error)
        end
        if music_choice == nil then
            return result.err(M.Error.CANCELLED)
        end
        if active_playlist.musics[music_choice.source_index] ~= music_choice.music then
            return result.err(M.Error.INVALID_SELECTION)
        end

        local played = schedule:playSelectedMusic(
            active_playlist,
            music_choice.source_index
        )
        if not played.ok then
            return result.err(played.err)
        end

        progress:refresh()
        notify("Ambient music: " .. played.value.name)
        return result.ok(nil)
    end, notify)
end

---@param notify? fun(message: string, level?: integer)
---@return AmbientResult<nil, any>
function M.select_current_playlist_music(notify)
    if type(notify) ~= "function" then
        return result.err(M.Error.INVALID_INPUT)
    end

    local current = selector:current()
    if not current.ok then
        return result.err(current.err)
    end

    local active_playlist = current.value
    ---@cast active_playlist AmbientPlayList
    if active_playlist:isEmpty() then
        return result.err(M.Error.EMPTY_PLAYLIST)
    end

    local initial_index = active_playlist.cursor
    if type(initial_index) ~= "number"
        or initial_index % 1 ~= 0
        or initial_index < 1
        or initial_index > #active_playlist.sorted_indices then
        return result.err(M.Error.INVALID_SELECTION)
    end

    local items = {}
    for position, source_index in ipairs(active_playlist.sorted_indices) do
        local music = active_playlist.musics[source_index]
        if music == nil then
            return result.err(M.Error.INVALID_SELECTION)
        end

        items[position] = {
            position     = position,
            source_index = source_index,
            music        = music,
        }
        if schedule.current_music ~= nil and music == schedule.current_music then
            initial_index = position
        end
    end

    return run(function()
        local music_choice, music_error = awaitSelect(items, {
            prompt        = "Select music",
            kind          = "ambient_current_playlist_music_selector",
            initial_index = initial_index,
            format_item   = function(item)
                return item.music.name
            end,
            snacks        = {
                on_show = function(picker)
                    picker.list:view(initial_index)
                end,
            },
        })
        if music_error ~= nil then
            return result.err(music_error)
        end
        if music_choice == nil then
            return result.err(M.Error.CANCELLED)
        end
        if active_playlist.musics[music_choice.source_index] ~= music_choice.music then
            return result.err(M.Error.INVALID_SELECTION)
        end

        local played = schedule:playSelectedMusic(
            active_playlist,
            music_choice.source_index
        )
        if not played.ok then
            return result.err(played.err)
        end

        progress:refresh()
        notify("Ambient music: " .. played.value.name)
        return result.ok(nil)
    end, notify)
end

return M
