local new = require("guaraci_cli.new")
local check = require("guaraci_cli.check")
local util = require("guaraci_cli.util")

local function run(args)
    local sink = { write = function() end }
    local err = {}
    local code = new.run(args, { stdout = sink, stderr = { write = function(_, s) err[#err + 1] = s end } })
    return code, table.concat(err)
end

describe("guaraci new", function()
    it("scaffolds the documented files and the generated view passes check", function()
        local dir = os.tmpname()
        os.remove(dir)
        local code = run({ dir })
        assert.are.equal(0, code)
        for _, f in ipairs({ "app.lua", "views/index.gc", "hooks/security_headers.lua", "cgi-bin/app.cgi",
            "spec/index_spec.lua", "paseo.json", ".gitignore", "Dockerfile.dev", "README.md" }) do
            assert.is_true(util.file_exists(dir .. "/" .. f), f)
        end
        assert.is_not_nil(util.read_file(dir .. "/paseo.json"):find('"dev": "guaraci dev"', 1, true))
        local clean = check.check_source("index.gc", util.read_file(dir .. "/views/index.gc"))
        assert.are.equal(0, #clean)
        os.execute("rm -rf '" .. dir .. "'")
    end)

    it("refuses non-empty directories and invalid names", function()
        local busy = os.tmpname()
        os.remove(busy)
        os.execute("mkdir -p '" .. busy .. "' && touch '" .. busy .. "/keep'")
        assert.are.equal(1, (run({ busy })))
        os.execute("rm -rf '" .. busy .. "'")
        assert.are.equal(2, (run({ "/tmp/bad name;rm" })))
        assert.are.equal(2, (run({})))
    end)

    it("treats an unlistable directory as non-empty", function()
        local real_popen = io.popen
        rawset(io, "popen", function() return { read = function() return nil end, close = function() return nil end } end)
        local target = os.tmpname()
        os.remove(target)
        os.execute("mkdir -p '" .. target .. "'")
        local code = run({ target })
        rawset(io, "popen", real_popen)
        os.execute("rm -rf '" .. target .. "'")
        assert.are.equal(1, code)
    end)
end)
