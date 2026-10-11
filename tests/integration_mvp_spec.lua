local hooks = require("hooks")
local guaraci = require("guaraci")

describe("MVP integration flow", function()
    before_each(function()
        hooks.clear()
    end)

    after_each(function()
        hooks.clear()
    end)

    it("renderiza template e injeta security headers", function()
        local res = guaraci.handle_request({
            method = "GET",
            path = "/",
            query = { nome = "Alice" }
        }, {
            templates_root = "views"
        })

        assert.are.equal(200, res.status)
        assert.is_not_nil(type(res.body) == "string" and res.body:find("Alice", 1, true))
        assert.are.equal("DENY", res.headers["X-Frame-Options"])
        assert.are.equal("nosniff", res.headers["X-Content-Type-Options"])
    end)

    it("faz short-circuit no before_request", function()
        hooks.register("before_request", function(req, res_state)
            res_state.status = 401
            res_state.body = "<h1>401 Unauthorized</h1>"
            return true
        end, "auth_gate")

        local res = guaraci.handle_request({
            method = "GET",
            path = "/",
            query = {}
        }, {
            templates_root = "views",
            auto_register_default_hooks = false
        })

        assert.are.equal(401, res.status)
        assert.is_not_nil(res.body:find("401", 1, true))
    end)
end)
