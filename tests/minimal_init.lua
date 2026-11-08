--- ntf's process hook: every worker that loads a spec gets this plugin, the two
--- things it needs at runtime, and the fixtures the specs share.

local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))

return {
    setup = function()
        vim.opt.runtimepath:prepend(root)
        for _, name in ipairs({ 'neotest', 'nvim-nio' }) do
            vim.opt.runtimepath:append(vim.fs.joinpath(root, '.deps', name))
        end
        package.path = vim.fs.joinpath(root, 'tests', '?.lua') .. ';' .. package.path
    end,
}
