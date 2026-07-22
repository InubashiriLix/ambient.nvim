local M = {
    cases = {},
}

local function inspect(value)
    if type(value) ~= "table" then
        return tostring(value)
    end

    local parts = {}
    for key, item in pairs(value) do
        table.insert(parts, tostring(key) .. "=" .. inspect(item))
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function equal(actual, expected, path)
    path = path or "value"
    if type(actual) ~= type(expected) then
        error(string.format("%s: expected %s, got %s", path, inspect(expected), inspect(actual)), 3)
    end

    if type(actual) ~= "table" then
        if actual ~= expected then
            error(
                string.format("%s: expected %s, got %s", path, inspect(expected), inspect(actual)),
                3
            )
        end
        return
    end

    for key, value in pairs(expected) do
        equal(actual[key], value, path .. "." .. tostring(key))
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            error(string.format("%s: unexpected key %s", path, tostring(key)), 3)
        end
    end
end

function M.test(name, fn)
    table.insert(M.cases, { name = name, fn = fn })
end

function M.eq(actual, expected)
    equal(actual, expected)
end

function M.truthy(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

function M.falsy(value, message)
    if value then
        error(message or "expected a falsy value", 2)
    end
end

function M.clearModules(...)
    for _, name in ipairs({ ... }) do
        package.loaded[name] = nil
    end
end

function M.run()
    local failures = 0
    for _, case in ipairs(M.cases) do
        local ok, err = xpcall(case.fn, debug.traceback)
        if ok then
            io.stdout:write("ok - " .. case.name .. "\n")
        else
            failures = failures + 1
            io.stderr:write("not ok - " .. case.name .. "\n" .. tostring(err) .. "\n")
        end
    end

    io.stdout:write(string.format("\n%d tests, %d failures\n", #M.cases, failures))
    if failures > 0 then
        os.exit(1)
    end
end

return M
