return {
    {
        "stevearc/conform.nvim",
        opts = function(_, opts)
            opts.formatters_by_ft = opts.formatters_by_ft or {}
            opts.formatters = opts.formatters or {}

            opts.formatters_by_ft.lua = { "emmylua-codeformat", lsp_format = "never" }
            opts.formatters["emmylua-codeformat"] = {
                command = "emmylua-codeformat",
                args = function(_, ctx)
                    local root = vim.fs.root(ctx.dirname, ".editorconfig")

                    if root then
                        return { "format", "-i", "-c", root .. "/.editorconfig" }
                    end

                    return { "format", "-i", "-d" }
                end,
                stdin = true,
            }
        end,
    },
}
