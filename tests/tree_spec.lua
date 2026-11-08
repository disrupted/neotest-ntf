local ntf = require('ntf')
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local tree = require('neotest-ntf.tree')

local path = '/repo/spec/x_spec.lua'

---@param node neotest.Tree
---@return string[]
local function names(node)
    return vim.tbl_map(function(child)
        return child:data().name
    end, node:children())
end

describe('neotest-ntf.tree', function()
    it('names every position by its file and its chain', function()
        local built = tree.build(path, { { names = { 'group', 'adds' }, row = 12 } })

        assert.equal(path, built:data().id)
        assert.equal('x_spec.lua', built:data().name)
        assert.equal('file', built:data().type)

        local group = built:children()[1]
        assert.equal(path .. '::group', group:data().id)
        assert.equal('namespace', group:data().type)

        local test = group:children()[1]
        assert.equal(path .. '::group::adds', test:data().id)
        assert.equal('test', test:data().type)
        assert.equal(path, test:data().path)
    end)

    it('keeps one namespace for the tests that share it', function()
        local built = tree.build(path, {
            { names = { 'group', 'adds' }, row = 12 },
            { names = { 'group', 'takes' }, row = 16 },
        })

        assert.same({ 'group' }, names(built))
        assert.same({ 'adds', 'takes' }, names(built:children()[1]))
    end)

    it('nests a describe inside the describe around it', function()
        local built =
            tree.build(path, { { names = { 'outer', 'inner', 'adds' }, row = 30 } })

        local inner = built:children()[1]:children()[1]
        assert.equal('inner', inner:data().name)
        assert.same({ 'adds' }, names(inner))
        assert.equal(path .. '::outer::inner::adds', inner:children()[1]:data().id)
    end)

    it('keeps two describes apart', function()
        local built = tree.build(path, {
            { names = { 'one', 'adds' }, row = 5 },
            { names = { 'two', 'adds' }, row = 9 },
        })

        assert.same({ 'one', 'two' }, names(built))
        assert.same({ 'adds' }, names(built:children()[1]))
        assert.same({ 'adds' }, names(built:children()[2]))
    end)

    it('takes the row a test was declared on', function()
        local built = tree.build(path, { { names = { 'group', 'adds' }, row = 12 } })

        assert.same({ 12, 0, 12, -1 }, built:children()[1]:children()[1]:data().range)
    end)

    it('gives a namespace the row of the first test it holds', function()
        local built = tree.build(path, { { names = { 'group', 'adds' }, row = 12 } })

        assert.same({ 12, 0, 12, -1 }, built:children()[1]:data().range)
    end)

    it('takes a test declared with no row as the first line', function()
        local built = tree.build(path, { { names = { 'adds' } } })

        assert.same({ 1, 0, 1, -1 }, built:children()[1]:data().range)
    end)

    it('holds only the file when it declares no test', function()
        local built = tree.build(path, {})

        assert.same({}, built:children())
        assert.same({ 1, 0, 1, -1 }, built:data().range)
    end)

    it('puts a test declared outside every describe under the file', function()
        local built = tree.build(path, { { names = { 'adds' }, row = 3 } })

        assert.same({ 'adds' }, names(built))
        assert.equal('test', built:children()[1]:data().type)
    end)
end)
