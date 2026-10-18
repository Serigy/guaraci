local main = require("guaraci_cli.main")
local util = require("guaraci_cli.util")

local function capture()
    local buf = { out = {}, err = {} }
    buf.streams = {
        stdout = { write = function(_, s) buf.out[#buf.out + 1] = s end },
        stderr = { write = function(_, s) buf.err[#buf.err + 1] = s end }
    }
    return buf
end

describe("guaraci cli main", function()
    it("prints version with exit 0", function()
        local c = capture()
        assert.are.equal(0, main.run({ "version" }, c.streams))
        assert.are.equal(require("guaraci_version") .. "\n", table.concat(c.out))
    end)

    it("prints help with exit 0", function()
        local c = capture()
        assert.are.equal(0, main.run({ "help" }, c.streams))
        assert.is_not_nil(table.concat(c.out):find("Usage: guaraci", 1, true))
    end)

    it("returns 2 for no command and unknown command", function()
        local c = capture()
        assert.are.equal(2, main.run({}, c.streams))
        assert.are.equal(2, main.run({ "bogus" }, c.streams))
    end)

    it("parses flags with inline and separate values", function()
        local parsed = util.parse_args({ "--json", "--mode", "text", "--port=99", "a.gc" },
            { value_flags = { mode = true, port = true } })
        assert.are.equal(true, parsed.flags.json)
        assert.are.equal("text", parsed.flags.mode)
        assert.are.equal("99", parsed.flags.port)
        assert.are.equal("a.gc", parsed.positional[1])
    end)

    it("reports unknown flags and missing values", function()
        assert.is_nil((util.parse_args({ "--nope" }, { flags = { json = true } })))
        assert.is_nil((util.parse_args({ "--mode" }, { value_flags = { mode = true } })))
    end)
end)
