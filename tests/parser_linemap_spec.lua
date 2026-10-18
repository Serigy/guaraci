local parser = require("parser")

describe("parser line map", function()
    it("maps compiled lines back to template lines", function()
        local tpl = "<h1>Oi</h1>\n<% if x then %>\n<p>a</p>\n<% end %>\n<%= nome %>\n"
        local code, meta = parser.compile(tpl)
        assert(code, "compile failed")
        assert(type(meta.line_map) == "table")
        local compiled_lines = {}
        for l in (code .. "\n"):gmatch("(.-)\n") do compiled_lines[#compiled_lines + 1] = l end
        local function template_line_of(snippet)
            for i, l in ipairs(compiled_lines) do
                if l:find(snippet, 1, true) then return meta.line_map[i] end
            end
        end
        assert(template_line_of("if x then") == 2)
        assert(template_line_of("tostring(nome") == 5)
        assert(template_line_of("\"HTML_TEXT\"") == 5)
    end)

    it("keeps multi-line code blocks aligned", function()
        local tpl = "a\n<%\nlocal x = 1\nlocal y = 2\n%>\nb"
        local code, meta = parser.compile(tpl)
        local n = 0
        for l in (code .. "\n"):gmatch("(.-)\n") do
            n = n + 1
            if l == "local y = 2" then
                assert(meta.line_map[n] == 4)
            end
        end
    end)

    it("reports position for unclosed tags", function()
        local code, err, pos = parser.compile("x\ny <% if")
        assert(code == nil and err)
        assert(pos.line == 2 and pos.col == 3)
    end)

    it("records expression contexts with positions", function()
        local _, meta = parser.compile("<script>\nvar a = <%= v %>;\n</script>")
        assert(meta.contexts[1] == "JS_STRING")
        assert(meta.context_info[1].line == 2 and meta.context_info[1].col == 9)
    end)

    it("compiles large templates quickly (line table built once)", function()
        local parts = {}
        for i = 1, 3000 do parts[i] = "line <%= x %>\n" end
        local started = os.clock()
        local code, meta = parser.compile(table.concat(parts))
        assert.is_not_nil(code)
        assert.are.equal(3000, #meta.context_info)
        assert.is_true(os.clock() - started < 5)
        assert.are.equal(3000, meta.context_info[3000].line)
    end)
end)
