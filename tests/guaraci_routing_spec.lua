local guaraci = require("guaraci")
local hooks = require("hooks")
local router_v2 = require("router_v2")
local middleware_chain = require("middleware_chain")
local context_store = require("context_store")

local function request(method, path, headers, opts)
    local o = { auto_register_default_hooks = false, templates_root = "views" }
    for k, v in pairs(opts or {}) do o[k] = v end
    return guaraci.handle_request({ method = method, path = path, headers = headers or {} }, o)
end

describe("handle_request wiring of router_v2 + middleware_chain", function()
    before_each(function()
        hooks.clear()
        router_v2.clear()
        middleware_chain.clear()
    end)

    after_each(function()
        router_v2.clear()
        middleware_chain.clear()
        hooks.clear()
    end)

    it("dispatches an explicit route with params", function()
        router_v2.get("/users/:id", function(req, res, ctx)
            res.body = "user:" .. ctx.params.id
        end)
        local res = request("GET", "/users/42")
        assert.are.equal(200, res.status)
        assert.are.equal("user:42", res.body)
    end)

    it("runs after_request hooks (security headers) for explicit routes", function()
        router_v2.get("/ping", function(req, res) res.body = "pong" end)
        local res = request("GET", "/ping", {}, { auto_register_default_hooks = true })
        assert.are.equal("pong", res.body)
        assert.are.equal("DENY", res.headers["X-Frame-Options"])
    end)

    it("falls back to the file-system router when no route matches", function()
        router_v2.get("/other", function(req, res) res.body = "x" end)
        local res = request("GET", "/", {}, { })
        assert.are.equal(200, res.status)
    end)

    it("returns 404 when neither router matches", function()
        router_v2.get("/other", function(req, res) res.body = "x" end)
        local res = request("GET", "/nao-existe-mesmo")
        assert.are.equal(404, res.status)
    end)

    it("global middleware short-circuits before the handler", function()
        local called = false
        router_v2.get("/secret", function(req, res) called = true end)
        guaraci.use(function(req, res)
            res.status = 401
            res.body = "denied"
            return true
        end, "deny_all")
        local res = request("GET", "/secret")
        assert.are.equal(false, called)
        assert.are.equal(401, res.status)
        assert.are.equal("denied", res.body)
    end)

    it("global middleware also guards the file-system router", function()
        guaraci.use(function(req, res)
            res.status = 401
            return true
        end, "deny_all")
        local res = request("GET", "/")
        assert.are.equal(401, res.status)
    end)

    it("csrf middleware rejects unsafe methods without token and accepts a matching pair", function()
        local hit = 0
        router_v2.post("/save", function(req, res) hit = hit + 1; res.body = "saved" end)
        guaraci.use(guaraci.middleware_csrf(), "csrf")

        local rejected = request("POST", "/save")
        assert.are.equal(403, rejected.status)
        assert.are.equal(0, hit)

        local token = string.rep("a", 24)
        local accepted = request("POST", "/save", {
            ["X-CSRF-Token"] = token,
            Cookie = "guaraci_csrf_token=" .. token
        })
        assert.are.equal(200, accepted.status)
        assert.are.equal(1, hit)
    end)

    it("group middleware runs for group routes and can short-circuit", function()
        local g = guaraci.group("/api")
        local called = false
        g.use(function(req, res)
            if req.headers["X-Key"] ~= "ok" then
                res.status = 401
                return true
            end
            return false
        end, "auth")
        g.get("/items", function(req, res) called = true; res.body = "items" end)

        local denied = request("GET", "/api/items")
        assert.are.equal(401, denied.status)
        assert.are.equal(false, called)

        local allowed = request("GET", "/api/items", { ["X-Key"] = "ok" })
        assert.are.equal(200, allowed.status)
        assert.are.equal("items", allowed.body)
    end)

    it("cleans the request context after the response", function()
        local seen_id
        router_v2.get("/ctx", function(req, res, ctx)
            seen_id = ctx.request_id
            assert(context_store.set(seen_id, "k", "v"))
            assert.are.equal("v", context_store.get(seen_id, "k"))
        end)
        request("GET", "/ctx")
        assert.is_not_nil(seen_id)
        assert.is_nil(context_store.get(seen_id, "k"))
    end)

    it("middleware failure becomes a generic 500 without leaking the error", function()
        guaraci.use(function() error("SECRET-DB-PASSWORD") end, "boom")
        local res = request("GET", "/")
        assert.are.equal(500, res.status)
        assert.is_nil(tostring(res.body):find("SECRET-DB-PASSWORD", 1, true))
    end)

    it("handler failure becomes a generic 500 without leaking the error", function()
        router_v2.get("/boom", function() error("SECRET-STACK") end)
        local res = request("GET", "/boom")
        assert.are.equal(500, res.status)
        assert.is_nil(tostring(res.body):find("SECRET-STACK", 1, true))
    end)

    it("after_request middleware runs for explicit routes", function()
        router_v2.get("/ar", function(req, res) res.body = "b" end)
        middleware_chain.use("after_request", function(req, res)
            res.headers["X-After"] = "1"
        end, "after")
        local res = request("GET", "/ar")
        assert.are.equal("1", res.headers["X-After"])
    end)
end)
