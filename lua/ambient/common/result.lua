local M = {}

---@class AmbientOk<T>
---@field ok true
---@field value T
---@field err nil

---@class AmbientErr<E>
---@field ok false
---@field value nil
---@field err E

---@alias AmbientResult<T, E> AmbientOk<T> | AmbientErr<E>

---@generic T
---@param value T
---@return AmbientOk<T>
function M.ok(value)
    return {
        ok    = true,
        value = value,
        err   = nil,
    }
end
---@generic E
---@param err E
---@return AmbientErr<E>
function M.err(err)
    return {
        ok    = false,
        value = nil,
        err   = err,
    }
end
return M
