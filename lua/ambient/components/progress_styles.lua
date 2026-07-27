local M = {}

---@type AmbientProgressCanonicalStyle
M.default = "braille"

---@param filled string
---@param empty string
---@param left? string
---@param right? string
---@return table
local function style(filled, empty, left, right)
    return {
        bar = {
            filled = filled,
            empty  = empty,
            left   = left or "",
            right  = right or "",
        },
    }
end

---@type table<AmbientProgressCanonicalStyle, table>
M.styles = {
    braille    = style("⠶", "⠄"),
    block      = style("█", "░"),
    line       = style("━", "─"),
    dots       = style("●", "○"),
    squares    = style("■", "□"),
    diamonds   = style("◆", "◇"),
    pipes      = style("▮", "▯"),
    ascii      = style("=", "-", "[", "]"),
    brackets   = style("█", "░", "[", "]"),
    angle      = style("━", "─", "〈", "〉"),
    powerline  = style("█", "░", "", ""),
    separators = style("⠶", "⠄", "", ""),
    rounded    = style("▰", "▱", "", ""),
    slanted    = style("▰", "▱", "", ""),
}

---@type table<string, AmbientProgressCanonicalStyle>
M.aliases = {
    default   = "braille",
    sparse    = "braille",
    classic   = "brackets",
    blocks    = "block",
    dense     = "block",
    bracket   = "brackets",
    old       = "brackets",
    dot       = "dots",
    square    = "squares",
    diamond   = "diamonds",
    pipe      = "pipes",
    separator = "separators",
    segment   = "separators",
    bubble    = "rounded",
    round     = "rounded",
}

---@param name string?
---@return string?
function M.canonical(name)
    if type(name) ~= "string" then
        return nil
    end

    if M.styles[name] ~= nil then
        return name
    end

    return M.aliases[name]
end

---@param name string?
---@return boolean
function M.is_valid(name)
    return M.canonical(name) ~= nil
end

---@param name string?
---@return table?
function M.resolve(name)
    local canonical = M.canonical(name)
    if canonical == nil then
        return nil
    end

    return M.styles[canonical]
end

---@return string[]
function M.names()
    local names = {}
    for name, _ in pairs(M.styles) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

---@return string
function M.describe()
    return table.concat(M.names(), ", ")
end

---@param config table
---@param name string?
---@return table
function M.apply(config, name)
    local preset      = M.resolve(name)
    local next_config = vim.deepcopy(config or {})
    if preset == nil then
        return next_config
    end

    next_config           = vim.tbl_deep_extend("force", next_config, vim.deepcopy(preset))
    next_config.bar       = next_config.bar or {}
    next_config.bar.style = M.canonical(name)
    return next_config
end

return M
