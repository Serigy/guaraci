local check = require("guaraci_cli.check")

local FIXTURES = "tests/fixtures/gc/"

local function run(args)
    local out, err = {}, {}
    local code = check.run(args, {
        stdout = { write = function(_, s) out[#out + 1] = s end },
        stderr = { write = function(_, s) err[#err + 1] = s end }
    })
    return code, table.concat(out), table.concat(err)
end

describe("guaraci check", function()
    it("exits 0 and prints nothing for a clean template", function()
        local code, out = run({ FIXTURES .. "ok.gc" })
        assert.are.equal(0, code)
        assert.are.equal("", out)
    end)

    it("maps Lua syntax errors to template lines", function()
        local code, out = run({ FIXTURES .. "lua_syntax.gc" })
        assert.are.equal(1, code)
        assert.is_not_nil(out:find("lua_syntax.gc:4:10: error: ", 1, true), out)
    end)

    it("maps errors inside multi-line blocks", function()
        local _, out = run({ FIXTURES .. "multiline.gc" })
        assert.is_not_nil(out:find("multiline.gc:4:", 1, true), out)
    end)

    it("reports unclosed tags and empty expressions", function()
        local _, out = run({ FIXTURES .. "unclosed.gc" })
        assert.is_not_nil(out:find("unclosed.gc:3:1: error", 1, true), out)
        local _, out2 = run({ FIXTURES .. "empty_expr.gc" })
        assert.is_not_nil(out2:find("empty_expr.gc:1:6: error", 1, true), out2)
    end)

    it("warns about JS/CSS contexts unless --mode text", function()
        local code, out = run({ FIXTURES .. "js_context.gc" })
        assert.are.equal(1, code)
        assert.is_not_nil(out:find(":3:12: warning", 1, true), out)
        assert.is_not_nil(out:find(":6:14: warning", 1, true), out)
        local code_text, out_text = run({ "--mode", "text", FIXTURES .. "js_context.gc" })
        assert.are.equal(0, code_text)
        assert.are.equal("", out_text)
    end)

    it("emits the documented JSON contract", function()
        local _, out = run({ "--json", FIXTURES .. "lua_syntax.gc" })
        local expected_shape = '^{"file":"tests/fixtures/gc/lua_syntax.gc","diagnostics":%[{"line":4,"col":10,"end_line":4,'
            .. '"severity":"error","code":"lua%-syntax","message":"[^"]+"}%]}\n$'
        assert.is_not_nil(out:match(expected_shape), out)
        local _, clean = run({ "--json", FIXTURES .. "ok.gc" })
        assert.are.equal('{"file":"tests/fixtures/gc/ok.gc","diagnostics":[]}\n', clean)
    end)

    it("returns 2 on usage errors and 1 for unreadable files", function()
        assert.are.equal(2, (run({})))
        assert.are.equal(2, (run({ "--bogus", "x.gc" })))
        assert.are.equal(2, (run({ "--mode", "xml", "x.gc" })))
        assert.are.equal(1, (run({ "tests/fixtures/gc/missing.gc" })))
    end)

    it("never executes template code", function()
        local path = os.tmpname()
        local fh = io.open(path, "w")
        fh:write("<% error('EXECUTED') %><% os.exit(7) %>")
        fh:close()
        local code = run({ path })
        os.remove(path)
        assert.are.equal(0, code)
    end)
end)
