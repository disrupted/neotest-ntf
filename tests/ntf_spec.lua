local ntf = require('ntf')
local describe, it, assert, pending = ntf.describe, ntf.it, ntf.assert, ntf.pending
local helpers = require('helpers')

local SPEC = {
    [[local ntf = require('ntf')]],
    [[local describe, it, assert = ntf.describe, ntf.it, ntf.assert]],
    '',
    [[describe('group', function()]],
    [[    it('adds', function()]],
    [[        assert.equal(2, 1 + 1)]],
    [[    end)]],
    [[    it('wants three', function()]],
    [[        assert.equal(3, 1 + 1)]],
    [[    end)]],
    [[end)]],
}

--- The ntf to run, when it is one that takes `--json`: this half of the specs
--- runs the adapter against the runner itself, so it pends rather than fails
--- where the ntf installed is older than the flags it needs.
---@return string? command, string? why_not
local function runner()
    local command = vim.env.NEOTEST_NTF or vim.fn.exepath('ntf')
    if command == '' then
        return nil, 'needs an ntf on $PATH (or $NEOTEST_NTF)'
    end

    local probe = helpers.file('probe_spec.lua', {
        [[local ntf = require('ntf')]],
        [[ntf.it('probe', function() end)]],
    })
    local listed = vim.system({ command, 'list', '--json', probe }, { text = true })
        :wait()
    if not pcall(vim.json.decode, listed.stdout) then
        return nil, 'needs an ntf that writes --json: ' .. command
    end
    return command
end

---@return string path of a project's spec
local function project()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(vim.fs.joinpath(dir, 'lua'), 'p')
    local path = vim.fs.joinpath(dir, 'spec', 'x_spec.lua')
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    vim.fn.writefile(SPEC, path)
    return path
end

---@param command string
---@param path string
---@return neotest-ntf.Adapter adapter, neotest.Tree tree
local function discovered(command, path)
    local adapter = require('neotest-ntf')({ command = { command } })
    return adapter,
        helpers.await(function()
            return adapter.discover_positions(path)
        end)
end

---@param adapter neotest-ntf.Adapter
---@param node neotest.Tree
---@return table<string, neotest.Result> mapped, integer code, string said
local function ran(adapter, node)
    local spec = adapter.build_spec({ tree = node })
    local outcome = vim.system(spec.command, { cwd = spec.cwd, text = true }):wait()
    local mapped = helpers.await(function()
        return adapter.results(spec, { code = outcome.code, output = outcome.stdout })
    end)
    return mapped, outcome.code, outcome.stderr
end

describe('neotest-ntf against ntf itself', function()
    it('discovers the names the spec declares', function()
        local command, why_not = runner()
        if not command then
            return pending(why_not)
        end

        local path = project()
        local _, tree = discovered(command, path)

        local group = tree:children()[1]
        assert.equal('group', group:data().name)
        assert.same(
            { 'adds', 'wants three' },
            vim.tbl_map(function(child)
                return child:data().name
            end, group:children())
        )
    end)

    it('reports the test it was narrowed to', function()
        local command, why_not = runner()
        if not command then
            return pending(why_not)
        end

        local path = project()
        local adapter, tree = discovered(command, path)
        local passing = tree:children()[1]:children()[1]

        local mapped, code, said = ran(adapter, passing)

        assert.equal(0, code, said)
        assert.equal('passed', mapped[passing:data().id].status)
        assert.equal(1, #vim.tbl_keys(mapped) - 1)
    end)

    it('reports every test of a file, and the file with them', function()
        local command, why_not = runner()
        if not command then
            return pending(why_not)
        end

        local path = project()
        local adapter, tree = discovered(command, path)

        local mapped, code, said = ran(adapter, tree)

        assert.equal(1, code, said)
        assert.equal('passed', mapped[path .. '::group::adds'].status)
        assert.equal('failed', mapped[path .. '::group::wants three'].status)
        assert.equal('failed', mapped[path].status)
    end)

    it('keeps what a failing test raised with its result', function()
        local command, why_not = runner()
        if not command then
            return pending(why_not)
        end

        local path = project()
        local adapter, tree = discovered(command, path)

        local mapped = ran(adapter, tree)
        local failed = mapped[path .. '::group::wants three']

        assert.equal('failed', failed.status)
        assert.is_true(failed.errors[1].message:find('3', 1, true) ~= nil)
    end)
end)
