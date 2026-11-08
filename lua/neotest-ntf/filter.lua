--- The `--filter` pattern that narrows a run to the position asked for.

local M = {}

--- A test matches its own full name, which ntf joins from the describe chain by
--- spaces; a namespace matches every name below it, which that chain starts
--- with.
---@param names string[] the describe/it chain, from the outermost describe down
---@param is_namespace boolean
---@return string pattern
function M.pattern(names, is_namespace)
    local pattern = '^' .. vim.pesc(table.concat(names, ' '))
    return is_namespace and (pattern .. ' ') or (pattern .. '$')
end

return M
