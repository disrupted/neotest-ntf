--- Turns the tests a document spells into the tree neotest walks.

---@class neotest-ntf.Node a position and the ones below it
---@field position neotest.Position
---@field children neotest-ntf.Node[]

local M = {}

---@param row integer?
---@return integer[]
local function line_range(row)
    return { row or 1, 0, row or 1, -1 }
end

---@param path string
---@param names string[]
---@return string
local function position_id(path, names)
    return table.concat(vim.list_extend({ path }, names), '::')
end

---@param position neotest.Position
---@return neotest-ntf.Node
local function node(position)
    return { position = position, children = {} }
end

---@param parent neotest-ntf.Node
---@param path string
---@param names string[]
---@param depth integer the depth of the namespace looked for
---@param row integer?
---@return neotest-ntf.Node
local function namespace_below(parent, path, names, depth, row)
    for _, child in ipairs(parent.children) do
        local position = child.position
        if position.type == 'namespace' and position.name == names[depth] then
            return child
        end
    end

    local created = node({
        type = 'namespace',
        path = path,
        name = names[depth] --[[@as string]],
        id = position_id(path, vim.list_slice(names, 1, depth)),
        -- ntf reports the line a test is declared on, not the one its describe
        -- is, so a namespace takes the line of the first test it holds
        range = line_range(row),
    })
    table.insert(parent.children, created)
    return created
end

---@param root neotest-ntf.Node
---@param path string
---@param names string[]
---@param row integer?
local function insert_test(root, path, names, row)
    local parent = root
    for depth = 1, #names - 1 do
        parent = namespace_below(parent, path, names, depth, row)
    end

    table.insert(
        parent.children,
        node({
            type = 'test',
            path = path,
            name = names[#names] --[[@as string]],
            id = position_id(path, names),
            range = line_range(row),
        })
    )
end

---@param root neotest-ntf.Node
---@return table the nested list `neotest.Tree.from_list` takes
local function as_list(root)
    local list = { root.position }
    for _, child in ipairs(root.children) do
        table.insert(list, as_list(child))
    end
    return list
end

---@param path string the spec file
---@param names string[]
---@return string the id neotest knows that test by
function M.id(path, names)
    return position_id(path, names)
end

---@param path string the spec file
---@param tests { names: string[], row: integer? }[] as `ntf list --json` spells them
---@return neotest.Tree
function M.build(path, tests)
    local root = node({
        type = 'file',
        path = path,
        name = vim.fs.basename(path),
        id = path,
        range = line_range(nil),
    })

    for _, test in ipairs(tests) do
        insert_test(root, path, test.names, test.row)
    end

    return require('neotest.types').Tree.from_list(as_list(root), function(position)
        return position.id
    end)
end

return M
