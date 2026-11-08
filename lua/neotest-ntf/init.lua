--- Neotest adapter for [ntf](https://github.com/notomo/ntf).
---
--- ntf runs busted-style `*_spec.lua` files, one nvim worker per test, and
--- speaks JSON: `ntf list --json` names every test as its spec declared it, and
--- `ntf run --json=FILE` writes the results to a file. Both are read here
--- instead of the source, so a name a spec builds at run time is the one
--- neotest runs and reports.
---
--- The results file is what an adapter has no other channel for: neotest
--- captures a command's streams into one pty, where the document could not be
--- told apart from what the tests themselves printed.

local control = require('nio.control')
local lib = require('neotest.lib')
local filter = require('neotest-ntf.filter')
local results = require('neotest-ntf.results')
local tree = require('neotest-ntf.tree')

---@class neotest-ntf.Config
---@field command? string[] the ntf executable, default `{ 'ntf' }`
---@field process_hook? string a Lua module every nvim process runs before it
---loads a spec; a project's `tests/minimal_init.lua` is taken when there is one
---@field args? string[] further arguments every run takes

---@class neotest-ntf.Adapter
---@field name string
---@field root fun(dir: string): string?
---@field is_test_file fun(path: string): boolean
---@field discover_positions fun(path: string): neotest.Tree
---@field build_spec fun(args: neotest.RunArgs): neotest.RunSpec?
---@field results fun(spec: neotest.RunSpec, result: neotest.StrategyResult): table<string, neotest.Result>

local M = {}

---@param config neotest-ntf.Config?
---@return neotest-ntf.Adapter
function M.create(config)
    config = config or {}
    local command = config.command or { 'ntf' }
    local project_root = lib.files.match_root_pattern('lua')

    ---@param subcommand string the command the flags below belong to, which ntf
    ---takes first
    ---@param hook string? the process hook this command runs
    ---@param args string[]
    ---@return string[]
    local function command_line(subcommand, hook, args)
        local line = vim.list_extend({}, command)
        table.insert(line, subcommand)
        if hook then
            table.insert(line, '--process-hook=' .. hook)
        end
        vim.list_extend(line, config.args or {})
        return vim.list_extend(line, args)
    end

    ---@param dir string
    ---@return string? path
    local function process_hook(dir)
        if config.process_hook then
            return config.process_hook
        end
        local candidate = vim.fs.joinpath(dir, 'tests', 'minimal_init.lua')
        return vim.uv.fs_stat(candidate) and candidate or nil
    end

    ---@async
    ---@param subcommand string
    ---@param cwd string
    ---@param args string[]
    ---@return table? document, string? failure
    local function document(subcommand, cwd, args)
        local future = control.future()
        local started, failure = pcall(
            vim.system,
            command_line(subcommand, process_hook(cwd), args),
            { text = true, cwd = cwd },
            function(outcome)
                if not future.is_set() then
                    future.set(outcome)
                end
            end
        )
        if not started then
            return nil, tostring(failure)
        end

        local outcome = future.wait()
        local decoded, decoded_document = pcall(vim.json.decode, outcome.stdout)
        if decoded and type(decoded_document) == 'table' then
            return decoded_document
        end
        local said = outcome.stderr ~= '' and outcome.stderr or outcome.stdout
        return nil, ('ntf wrote no document (exit %d): %s'):format(outcome.code, said)
    end

    ---@async
    ---@param path string
    ---@return neotest.Tree
    local function discover_positions(path)
        local listed, failure =
            document('list', project_root(path) or vim.fs.dirname(path), {
                '--json',
                path,
            })
        if not listed then
            error(failure)
        end
        return tree.build(path, listed.tests)
    end

    ---@param node neotest.Tree the node a run was asked for
    ---@return string? pattern
    local function filter_of(node)
        local position = node:data()
        if position.type ~= 'namespace' and position.type ~= 'test' then
            return nil
        end

        local names = { position.name }
        for parent in node:iter_parents() do
            local above = parent:data()
            if above.type ~= 'namespace' then
                break
            end
            table.insert(names, 1, above.name)
        end

        return filter.pattern(names, position.type == 'namespace')
    end

    ---@param args neotest.RunArgs
    ---@return neotest.RunSpec?
    local function build_spec(args)
        local node = args.tree
        if not node then
            return nil
        end

        local position = node:data()
        local cwd = project_root(position.path) or vim.fs.dirname(position.path)
        local results_path = vim.fn.tempname()

        local argv = { '--json=' .. results_path }
        local pattern = filter_of(node)
        if pattern then
            table.insert(argv, '--filter=' .. pattern)
        end
        vim.list_extend(argv, args.extra_args or {})
        table.insert(argv, position.path)

        return {
            command = command_line('run', process_hook(cwd), argv),
            cwd = cwd,
            context = {
                file = position.path,
                cwd = cwd,
                results_path = results_path,
            },
        }
    end

    ---@async
    ---@param spec neotest.RunSpec
    ---@param result neotest.StrategyResult
    ---@return table<string, neotest.Result>
    local function collect(spec, result)
        local context = spec.context or {}
        local read, raw = pcall(lib.files.read, context.results_path)
        local decoded = read and select(2, pcall(vim.json.decode, raw)) or nil
        return results.map(context, decoded, result and result.code or 1)
    end

    return {
        name = 'neotest-ntf',
        root = project_root,
        is_test_file = function(path)
            return vim.endswith(path, '_spec.lua')
        end,
        discover_positions = discover_positions,
        build_spec = build_spec,
        results = collect,
    }
end

local Adapter = M.create({})

setmetatable(Adapter, {
    __call = function(_, config)
        return M.create(config)
    end,
})

return Adapter
