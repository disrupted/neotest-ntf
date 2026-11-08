local ntf = require('ntf')
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local results = require('neotest-ntf.results')

local file = '/repo/spec/x_spec.lua'

---@param overrides table? what the entry differs in from a passing test
---@return table
local function entry(overrides)
    return vim.tbl_extend('force', {
        file = 'spec/x_spec.lua',
        names = { 'group', 'adds' },
        status = 'passed',
    }, overrides or {})
end

---@param document table? the run's document
---@param code integer? the run's exit code
---@return table<string, neotest.Result>
local function mapped(document, code)
    return results.map(
        { file = file, cwd = '/repo', results_path = '/tmp/document.json' },
        document,
        code or 0
    )
end

---@return fun(text: string): string where the output went, table<string, true> what it was handed
local function keeper()
    local kept = {}
    local writer = function(text)
        table.insert(kept, text)
        return ('/tmp/output-%d'):format(#kept)
    end
    return writer, kept
end

describe('neotest-ntf.results', function()
    it('maps the statuses neotest knows', function()
        local mapped_results = mapped({
            results = {
                entry({ names = { 'passed' } }),
                entry({ names = { 'failed' }, status = 'failed' }),
                entry({ names = { 'errored' }, status = 'error' }),
                entry({ names = { 'pending' }, status = 'pending' }),
            },
        })

        assert.equal('passed', mapped_results[file .. '::passed'].status)
        assert.equal('failed', mapped_results[file .. '::failed'].status)
        assert.equal('failed', mapped_results[file .. '::errored'].status)
        assert.equal('skipped', mapped_results[file .. '::pending'].status)
    end)

    it('keys a result by its file and its chain', function()
        local mapped_results = mapped({ results = { entry() } })

        assert.is_true(mapped_results[file .. '::group::adds'] ~= nil)
    end)

    it('resolves the path the document spells against the run directory', function()
        local mapped_results = results.map(
            { file = 'spec', cwd = '/repo', results_path = '/tmp/document.json' },
            { results = { entry() } },
            0
        )

        assert.is_true(mapped_results[file .. '::group::adds'] ~= nil)
    end)

    it('keeps an absolute path the document spells as it is', function()
        local mapped_results = mapped({ results = { entry({ file = file }) } })

        assert.is_true(mapped_results[file .. '::group::adds'] ~= nil)
    end)

    it('keeps the first line of a message short, and all of it as the error', function()
        local mapped_results = mapped({
            results = { entry({ status = 'failed', message = 'boom\nat line 5' }) },
        })

        local result = mapped_results[file .. '::group::adds']
        assert.equal('boom', result.short)
        assert.equal('boom\nat line 5', result.errors[1].message)
    end)

    it('leaves a passing test without a message or an output', function()
        local mapped_results = mapped({ results = { entry() } })

        local result = mapped_results[file .. '::group::adds']
        assert.is_nil(result.short)
        assert.is_nil(result.errors)
        assert.is_nil(result.output)
    end)

    it('stores what a test printed through the writer it is given', function()
        local writer, kept = keeper()
        local mapped_results = results.map(
            { file = file, cwd = '/repo', results_path = '/tmp/document.json' },
            { results = { entry({ output = 'from print\n' }) } },
            0,
            writer
        )

        assert.same({ 'from print\n' }, kept)
        assert.equal('/tmp/output-1', mapped_results[file .. '::group::adds'].output)
    end)

    it('leaves an empty output alone', function()
        local writer, kept = keeper()
        results.map(
            { file = file, cwd = '/repo', results_path = '/tmp/document.json' },
            { results = { entry({ output = '' }) } },
            0,
            writer
        )

        assert.same({}, kept)
    end)

    it('passes the file the run asked for with its exit code', function()
        assert.equal('passed', mapped({ results = {} }, 0)[file].status)
        assert.equal('failed', mapped({ results = {} }, 1)[file].status)
    end)

    it('puts a load error on the file the run asked for', function()
        local mapped_results = mapped({
            results = {},
            load_errors = { { file = 'spec/broken_spec.lua', message = 'boom' } },
        })

        assert.same(
            { { message = 'spec/broken_spec.lua: boom' } },
            mapped_results[file].errors
        )
    end)

    it('leaves the file without errors when nothing failed to load', function()
        assert.is_nil(mapped({ results = {} }, 0)[file].errors)
    end)

    it('fails the file when ntf wrote no document', function()
        local mapped_results = results.map(
            { file = file, cwd = '/repo', results_path = '/tmp/document.json' },
            nil,
            1
        )

        assert.equal('failed', mapped_results[file].status)
        assert.equal('ntf wrote no document', mapped_results[file].short)
    end)
end)
