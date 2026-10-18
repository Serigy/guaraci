local cli_test = require("guaraci_cli.test")

describe("guaraci test discovery", function()
    it("finds spec files and converts paths to module names", function()
        local modules, dir = cli_test.discover("tests")
        assert.are.equal("tests", dir)
        local found = false
        for _, name in ipairs(modules) do
            if name == "tests.cli_test_spec" then found = true end
        end
        assert.is_true(found)
    end)

    it("returns nothing for a missing directory", function()
        local modules = cli_test.discover("no_such_dir_xyz")
        assert.are.equal(0, #modules)
    end)
end)
