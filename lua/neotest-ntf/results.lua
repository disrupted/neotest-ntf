--- Turns a run's document into the results neotest reads, keyed by position id.

local M = {}

---@type table<string, neotest.ResultStatus>
M.STATUS = {
    passed = 'passed',
    failed = 'failed',
    error = 'failed',
    pending = 'skipped',
}

---@param base string
---@param path string
---@return string
function M.absolute(base, path)
    if path:sub(1, 1) == '/' or path:find('^%a:[/\\]') then
        return vim.fs.normalize(path)
    end
    return vim.fs.normalize(vim.fs.joinpath(base, path))
end

---@param text string
---@return string path the file neotest reads that test's output from
local function write_output(text)
    local path = vim.fn.tempname()
    local file = assert(io.open(path, 'w'))
    file:write(text)
    file:close()
    return path
end

---@class neotest-ntf.Context what a run keeps between building its spec and
---reading its results
---@field file string the file or directory that was run
---@field cwd string the directory the document's relative paths are relative to
---@field results_path string the file the document is written to

---@param base string the directory the document's paths are relative to
---@param entry table one test of the document
---@param write fun(text: string): string? stores the output, returning where it went
---@return string id, neotest.Result
local function as_result(base, entry, write)
    local result = {
        status = M.STATUS[entry.status] or 'failed',
        short = entry.message and entry.message:gsub('\n.*$', '') or nil,
    }

    if entry.message then
        result.errors = { { message = entry.message } }
    end

    if entry.output and entry.output ~= '' then
        result.output = write(entry.output)
    end

    return table.concat(
        vim.list_extend({ M.absolute(base, entry.file) }, entry.names),
        '::'
    ),
        result
end

---@param context neotest-ntf.Context
---@param document table? the decoded document, nil when ntf wrote none
---@param code integer the run's exit code
---@param write? fun(text: string): string? where a test's output goes, for the callers that do not want files
---@return table<string, neotest.Result>
function M.map(context, document, code, write)
    write = write or write_output

    if type(document) ~= 'table' then
        return {
            [context.file] = {
                status = 'failed',
                short = 'ntf wrote no document',
            },
        }
    end

    local mapped = {}
    for _, entry in ipairs(document.results or {}) do
        local id, result = as_result(context.cwd, entry, write)
        mapped[id] = result
    end

    local errors = {}
    for _, load_error in ipairs(document.load_errors or {}) do
        table.insert(errors, {
            message = ('%s: %s'):format(load_error.file, load_error.message),
        })
    end

    mapped[context.file] = {
        status = code == 0 and 'passed' or 'failed',
        errors = #errors > 0 and errors or nil,
    }
    return mapped
end

return M
