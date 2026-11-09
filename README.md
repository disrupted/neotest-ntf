# neotest-ntf

[Neotest](https://github.com/nvim-neotest/neotest) adapter for
[ntf](https://github.com/notomo/ntf), the dependency-free test runner for Neovim
plugins.

Discovery and results come from ntf's JSON documents rather than from the spec
source, so a name a spec builds at run time (`it('case ' .. n)`) is the name
Neotest runs and reports. What a test printed rides on its own result, and a
describe narrows a run with `--filter`.

## Requirements

- Neovim 0.10 or later, with Neotest and
  [nvim-nio](https://github.com/nvim-neotest/nvim-nio)
- an `ntf` that takes `--json` (`ntf list --json`, `ntf run --json=FILE`)
- ntf itself needs Neovim 0.12 or later for its workers

## Setup

```lua
require('neotest').setup({
    adapters = {
        require('neotest-ntf'),
    },
})
```

It runs `ntf` from `$PATH`, and takes a project's `tests/minimal_init.lua` as
the process hook when it has one. Either can be given explicitly:

```lua
require('neotest-ntf')({
    command = { 'mise', 'exec', '--', 'ntf' },
    process_hook = './tests/minimal_init.lua',
    args = {},
})
```

## Development

```sh
mise run deps   # neotest and nvim-nio into .deps/
mise run test   # the specs, run by ntf itself
mise run lint   # stylua --check
```

`:help neotest-ntf` (doc/neotest-ntf.txt) has the options and the known limits.

## License

MIT
