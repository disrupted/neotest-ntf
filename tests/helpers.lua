--- Fixtures and helpers the specs share.

local nio = require('nio')

local M = {}

---@param func function
---@return ... what the task returned, raising what it raised
function M.await(func)
    local outcome, done = nil, false
    nio.run(function()
        outcome = { pcall(func) }
        done = true
    end)
    vim.wait(30000, function()
        return done
    end, 10)

    assert(outcome, 'the task never finished')
    assert(outcome[1], outcome[2])
    return unpack(outcome, 2)
end

---@param name string
---@param lines string[]
---@return string path
function M.file(name, lines)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local path = vim.fs.joinpath(dir, name)
    vim.fn.writefile(lines, path)
    return path
end

---@param document table
---@return string path
function M.document(document)
    return M.file(
        'document.json',
        vim.split(vim.json.encode(document), '\n', { plain = true })
    )
end

--- An `ntf` that answers with whatever document the spec put in
--- `$NTF_STUB_DOCUMENT`, and files the command line it was given in
--- `$NTF_STUB_ARGV`: the adapter's half of the contract, without a test run.
---@return string path
function M.stub()
    local path = M.file('ntf', {
        '#!/bin/sh',
        'printf "%s\\n" "$*" > "$NTF_STUB_ARGV"',
        'out=""',
        'for arg in "$@"; do',
        '  case "$arg" in',
        '    --json=*) out="${arg#--json=}" ;;',
        '  esac',
        'done',
        'if [ -n "$out" ]; then cp "$NTF_STUB_DOCUMENT" "$out"; else cat "$NTF_STUB_DOCUMENT"; fi',
    })
    vim.uv.fs_chmod(path, 493)
    return path
end

---@return string path of the file the stub files its command line in
function M.argv_file()
    return M.file('argv', { '' })
end

---@param document table
---@return string stub, string argv_file
function M.adapter_command(document)
    local argv_file = M.argv_file()
    vim.env.NTF_STUB_ARGV = argv_file
    vim.env.NTF_STUB_DOCUMENT = M.document(document)
    return M.stub(), argv_file
end

---@param path string
---@return string
function M.argv(path)
    return (table.concat(vim.fn.readfile(path), '\n'))
end

---@param path string
---@return string[]
function M.split_argv(path)
    return vim.split(M.argv(path), ' ', { trimempty = true })
end

---@param dir string
---@param name string
---@return string path of the spec file, which is what a project root holds
function M.spec_file(dir, name)
    local path = vim.fs.joinpath(dir, name)
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    vim.fn.writefile({ 'return {}' }, path)
    return path
end

return M
