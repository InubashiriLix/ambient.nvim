local result   = require("ambient.result")
local newTable = require("table.new")

---@class QueueConfig
---@field max_size integer

---@enum QueueError
local QueueError = {
    INVALID_CONFIG = "INVALID_CONFIG",
    QUEUE_FULL     = "QUEUE_FULL",
}

---@class Queue<T>
---@field private config QueueConfig
---@field private items table<integer, T?>
---@field private head integer
---@field private tail integer
---@field private size integer
---@field Error table<string, QueueError>
---@field __index Queue<any>
local M = {}

M.Error = QueueError
M.__index = M

---@generic T
---@param config QueueConfig
---@return AmbientResult<Queue<T>, QueueError>
function M.new(config)
    if config == nil
        or type(config.max_size) ~= "number"
        or config.max_size <= 0
        or config.max_size ~= math.floor(config.max_size) then
        return result.err(M.Error.INVALID_CONFIG)
    end

    local obj = {
        config = config,
        items  = newTable(config.max_size, 0),
        head   = 1,
        tail   = 1,
        size   = 0,
    }

    return result.ok(setmetatable(obj, M))
end

---@generic T
---@param self Queue<T>
---@param item T
---@return AmbientResult<nil, QueueError>
function M:enqueue(item)
    if self:isFull() then
        return result.err(M.Error.QUEUE_FULL)
    end

    self.items[self.tail] = item
    self.tail             = self:nextPivot(self.tail)
    self.size             = self.size + 1

    return result.ok(nil)
end

---@generic T
---@param self Queue<T>
---@return AmbientResult<T?, QueueError>
function M:dequeue()
    if self:isEmpty() then
        return result.ok(nil)
    end

    local item            = self.items[self.head]
    self.items[self.head] = nil
    self.head            = self:nextPivot(self.head)
    self.size            = self.size - 1

    return result.ok(item)
end

---@generic T
---@param self Queue<T>
---@param index integer 1-based offset from the current head.
---@return AmbientResult<T?, QueueError>
function M:peek(index)
    if index < 1 or index > self.size then
        return result.ok(nil)
    end

    local item_index = ((self.head + index - 2) % self.config.max_size) + 1

    return result.ok(self.items[item_index])
end

---@generic T
---@param self Queue<T>
---@return integer
function M:getSize()
    return self.size
end

---@generic T
---@param self Queue<T>
---@return boolean
function M:isEmpty()
    return self.size == 0
end

---@generic T
---@param self Queue<T>
---@return boolean
function M:isFull()
    return self.size == self.config.max_size
end

---@generic T
---@param self Queue<T>
---@return nil
function M:del()
    for index = 1, self.config.max_size do
        self.items[index] = nil
    end

    self.head = 1
    self.tail = 1
    self.size = 0
end

---@generic T
---@param self Queue<T>
---@param index integer
---@return integer
function M:nextPivot(index)
    return index % self.config.max_size + 1
end

return M
