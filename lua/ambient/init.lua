local M = {}

---@param opts? AmbientConfig
---@return AmbientResult<AmbientConfig, AmbientConfigError>
function M.setup(opts)
    return require("ambient.config").setup(opts)
end
---@return AmbientResult<AmbientConfig, AmbientConfigError>
function M.get_config()
    return require("ambient.config").get()
end
function M.start()
    -- TODO: implement the scheduler start function
end
function M.stop()
    -- TODO: implement the scheduler stop function
end
return M
