local ntf = require('ntf')
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local adapter_module = require('neotest-ntf')
local helpers = require('helpers')

---@param document table? the document the stub answers with
---@param config table? what the adapter differs in from its defaults
---@return neotest-ntf.Adapter adapter, string argv_file
local function adapter(document, config)
    local stub, argv_file = helpers.adapter_command(document or {
        tests = {},
        results = {},
    })
    local opts = vim.tbl_extend('force', { command = { stub } }, config or {})
    return adapter_module(opts), argv_file
end

---@param path string the file or directory
---@param name string what that path is called
---@return neotest.Tree
local function position(path, name)
    return require('neotest.types').Tree.from_list({
        {
            type = 'file',
            path = path,
            name = name,
            id = path,
            range = { 1, 0, 1, -1 },
        },
    }, function(pos)
        return pos.id
    end)
end

---@return string dir of a project, holding a lua directory and a spec
local function project()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(vim.fs.joinpath(dir, 'lua'), 'p')
    return dir, helpers.spec_file(dir, 'spec/x_spec.lua')
end

---@param args string[]
---@return string[] the flags among them
local function flags(args)
    return vim.tbl_filter(function(arg)
        return arg:find('^%-%-') ~= nil
    end, args)
end

describe('neotest-ntf adapter', function()
    it('is a test file only for the specs ntf discovers', function()
        local adapter_ = adapter_module({})

        assert.is_true(adapter_.is_test_file('/repo/spec/x_spec.lua'))
        assert.is_true(not adapter_.is_test_file('/repo/lua/x.lua'))
    end)

    it('lists a spec through the command it was given', function()
        local adapter_, argv_file = adapter({ tests = {} })
        local _, path = project()

        helpers.await(function()
            adapter_.discover_positions(path)
        end)

        assert.same({ 'list', '--json', path }, helpers.split_argv(argv_file))
    end)

    it('builds the tree the listing spells', function()
        local adapter_ = adapter({
            tests = {
                { names = { 'group', 'adds' }, row = 12 },
                { names = { 'group', 'takes' }, row = 16 },
            },
        })
        local _, path = project()

        local built = helpers.await(function()
            return adapter_.discover_positions(path)
        end)

        local group = built:children()[1]
        assert.equal('group', group:data().name)
        assert.same({ 12, 0, 12, -1 }, group:data().range)
        assert.equal(path .. '::group::adds', group:children()[1]:data().id)
    end)

    it('runs a whole file when the file is asked for', function()
        local adapter_ = adapter()
        local _, path = project()

        local spec = adapter_.build_spec({ tree = position(path, 'x_spec.lua') })

        assert.equal('run', spec.command[2])
        assert.equal(path, spec.command[#spec.command])
        assert.same({ '--json=' .. spec.context.results_path }, flags(spec.command))
    end)

    it('narrows a run to one test by its full name', function()
        local adapter_ = adapter()
        local _, path = project()

        local built = require('neotest-ntf.tree').build(path, {
            { names = { 'group', 'adds' }, row = 12 },
        })
        local spec = adapter_.build_spec({ tree = built:children()[1]:children()[1] })

        assert.is_true(vim.tbl_contains(flags(spec.command), '--filter=^group adds$'))
        assert.is_true(
            vim.tbl_contains(
                flags(spec.command),
                '--json=' .. spec.context.results_path
            )
        )
        assert.equal(path, spec.command[#spec.command])
    end)

    it('narrows a run to the names below a describe', function()
        local adapter_ = adapter()
        local _, path = project()

        local built = require('neotest-ntf.tree').build(path, {
            { names = { 'group', 'adds' }, row = 12 },
        })
        local spec = adapter_.build_spec({ tree = built:children()[1] })

        assert.is_true(vim.tbl_contains(flags(spec.command), '--filter=^group '))
    end)

    it('keeps the run in the project the spec belongs to', function()
        local adapter_ = adapter()
        local dir, path = project()

        local spec = adapter_.build_spec({ tree = position(path, 'x_spec.lua') })

        assert.equal(dir, spec.cwd)
        assert.equal(dir, spec.context.cwd)
        assert.equal(path, spec.context.file)
    end)

    it('keeps the run in the directory of a spec outside every project', function()
        local adapter_ = adapter()
        local path = helpers.file('lone_spec.lua', { 'return {}' })

        local spec = adapter_.build_spec({ tree = position(path, 'lone_spec.lua') })

        assert.equal(vim.fs.dirname(path), spec.cwd)
    end)

    it('files the document where the results are read from', function()
        local adapter_ = adapter()
        local _, path = project()

        local spec = adapter_.build_spec({ tree = position(path, 'x_spec.lua') })

        assert.is_true(
            vim.tbl_contains(
                flags(spec.command),
                '--json=' .. spec.context.results_path
            )
        )
    end)

    it('takes a project\'s tests/minimal_init.lua as the process hook', function()
        local adapter_ = adapter()
        local dir, path = project()
        local hook = helpers.spec_file(dir, 'tests/minimal_init.lua')

        local spec = adapter_.build_spec({ tree = position(path, 'x_spec.lua') })

        assert.is_true(vim.tbl_contains(flags(spec.command), '--process-hook=' .. hook))
    end)

    it('takes the process hook it was configured with over the project one', function()
        local adapter_ = adapter(nil, { process_hook = '/fixtures/hook.lua' })
        local dir, path = project()
        helpers.spec_file(dir, 'tests/minimal_init.lua')

        local spec = adapter_.build_spec({ tree = position(path, 'x_spec.lua') })

        assert.is_true(
            vim.tbl_contains(flags(spec.command), '--process-hook=/fixtures/hook.lua')
        )
    end)

    it('leaves the process hook out where the project has none', function()
        local adapter_ = adapter()
        local path = helpers.file('lone_spec.lua', { 'return {}' })

        local spec = adapter_.build_spec({ tree = position(path, 'lone_spec.lua') })

        assert.is_true(
            not vim.tbl_contains(
                flags(spec.command),
                '--process-hook=/fixtures/hook.lua'
            )
        )
        assert.same({ '--json=' .. spec.context.results_path }, flags(spec.command))
    end)

    it('passes what the caller asked for on to the run', function()
        local adapter_ = adapter()
        local _, path = project()

        local spec = adapter_.build_spec({
            tree = position(path, 'x_spec.lua'),
            extra_args = { '--jobs=2' },
        })

        assert.is_true(vim.tbl_contains(spec.command, '--jobs=2'))
    end)

    it('adds the flags it was configured with to every command', function()
        local adapter_ = adapter(nil, { args = { '--timeout=1000' } })
        local _, path = project()

        local spec = adapter_.build_spec({ tree = position(path, 'x_spec.lua') })

        assert.is_true(vim.tbl_contains(spec.command, '--timeout=1000'))
    end)

    it('never builds a spec for a run that named no position', function()
        local adapter_ = adapter()

        assert.is_nil(adapter_.build_spec({}))
    end)

    it('reads the results the run filed', function()
        local adapter_ = adapter({
            results = {
                {
                    file = 'spec/x_spec.lua',
                    names = { 'group', 'adds' },
                    status = 'failed',
                    message = 'boom',
                },
            },
        })
        local _, path = project()
        local spec = adapter_.build_spec({ tree = position(path, 'x_spec.lua') })

        local outcome = vim.system(spec.command, { cwd = spec.cwd, text = true }):wait()
        local mapped = helpers.await(function()
            return adapter_.results(
                spec,
                { code = outcome.code, output = outcome.stdout }
            )
        end)

        local id = path .. '::group::adds'
        assert.equal('failed', mapped[id].status)
        assert.equal('boom', mapped[id].short)
        assert.equal('passed', mapped[path].status)
    end)

    it('reports the file when the run filed no document', function()
        local adapter_ = adapter()
        local _, path = project()
        local spec = adapter_.build_spec({ tree = position(path, 'x_spec.lua') })
        os.remove(spec.context.results_path)

        local mapped = helpers.await(function()
            return adapter_.results(spec, { code = 1 })
        end)

        assert.equal('failed', mapped[path].status)
        assert.equal('ntf wrote no document', mapped[path].short)
    end)
end)
