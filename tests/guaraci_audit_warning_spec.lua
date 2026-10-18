describe("guaraci_audit write failures", function()
    it("warns once on stderr when the log cannot be written", function()
        package.loaded["guaraci_audit"] = nil
        local audit = require("guaraci_audit")
        audit.set_log_path("/nonexistent-dir-for-test/audit.log")
        local real_stderr = io.stderr
        local seen = {}
        rawset(io, "stderr", { write = function(_, ...) seen[#seen + 1] = table.concat({ ... }) end })
        audit.log_security("first", {})
        audit.log_security("second", {})
        rawset(io, "stderr", real_stderr)
        package.loaded["guaraci_audit"] = nil
        assert.are.equal(1, #seen)
        assert.is_not_nil(seen[1]:find("cannot write audit log", 1, true))
    end)
end)
