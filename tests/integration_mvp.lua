local hooks = require("hooks")
local guaraci = require("guaraci")

local M = {}

local function assert_true(value, message)
    if not value then
        error(message)
    end
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_eq failed") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

function M.run()
    hooks.clear()

    local res = guaraci.handle_request({
        method = "GET",
        path = "/",
        query = { nome = "Alice" }
    }, {
        templates_root = "views"
    })

    assert_eq(res.status, 200, "status deve ser 200")
    assert_true(type(res.body) == "string" and res.body:find("Alice", 1, true) ~= nil,
        "body deve conter nome renderizado")
    assert_eq(res.headers["X-Frame-Options"], "DENY", "security header X-Frame-Options")
    assert_eq(res.headers["X-Content-Type-Options"], "nosniff", "security header X-Content-Type-Options")

    local blocked = false
    hooks.clear()
    hooks.register("before_request", function(req, res_state)
        res_state.status = 401
        res_state.body = "<h1>401 Unauthorized</h1>"
        return true
    end, "auth_gate")

    local res_blocked = guaraci.handle_request({
        method = "GET",
        path = "/",
        query = {}
    }, {
        templates_root = "views",
        auto_register_default_hooks = false
    })

    if res_blocked.status == 401 then
        blocked = true
    end

    assert_true(blocked, "hook before_request deve fazer short-circuit")

    hooks.clear()
    return true
end

return M
