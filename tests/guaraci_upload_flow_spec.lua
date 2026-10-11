local hooks = require("hooks")

describe("Guaraci upload flow (Phase 12)", function()
    local original_guaraci
    local original_file_manager

    before_each(function()
        hooks.clear()
        original_guaraci = package.loaded["guaraci"]
        original_file_manager = package.loaded["file_manager"]
    end)

    after_each(function()
        package.loaded["guaraci"] = original_guaraci
        package.loaded["file_manager"] = original_file_manager
    end)

    it("faz short-circuit padronizado para upload_error e cleanup por request_id", function()
        local observed_request_id

        package.loaded["file_manager"] = {
            cleanup_request = function(request_id)
                observed_request_id = request_id
                return true
            end
        }

        package.loaded["guaraci"] = nil
        local guaraci = require("guaraci")

        local res = guaraci.handle_request({
            method = "POST",
            path = "/upload",
            context_id = "req-upload-77",
            upload_error = "file_too_large"
        }, {
            auto_register_default_hooks = false
        })

        assert.are.equal(413, res.status)
        assert.is_true(type(res.body) == "string")
        assert.is_true(res.body:find("upload_error") ~= nil)
        assert.are.equal("req-upload-77", observed_request_id)
    end)
end)
