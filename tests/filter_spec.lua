local ntf = require('ntf')
local describe, it, assert = ntf.describe, ntf.it, ntf.assert
local filter = require('neotest-ntf.filter')

describe('neotest-ntf.filter', function()
    it('narrows a run to one test by its full name', function()
        assert.equal('^group adds$', filter.pattern({ 'group', 'adds' }, false))
    end)

    it('narrows a run to the names below a describe', function()
        assert.equal('^group ', filter.pattern({ 'group' }, true))
    end)

    it('narrows to a nested describe by the chain above it', function()
        assert.equal('^outer inner ', filter.pattern({ 'outer', 'inner' }, true))
    end)

    it('escapes the characters a name may spell', function()
        assert.equal(
            '^group %(a %- b%)%.$',
            filter.pattern({ 'group', '(a - b).' }, false)
        )
    end)
end)
