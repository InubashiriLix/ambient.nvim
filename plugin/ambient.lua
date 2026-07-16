if vim.g.loaded_ambient_nvim == 1 then
    return
end

vim.g.loaded_ambient_nvim = 1

require("ambient").register_commands()
