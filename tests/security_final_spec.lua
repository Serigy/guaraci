local guaraci = require("guaraci")
local hooks = require("hooks")
local router_v2 = require("router_v2")
local middleware_chain = require("middleware_chain")

local function reset()
    hooks.clear(); router_v2.clear(); middleware_chain.clear()
end

local function get(path, opts, method)
    return guaraci.handle_request({ method = method or "GET", path = path, headers = {} }, opts or {})
end

describe("security headers on every response", function()
    before_each(reset)
    after_each(reset)

    it("404 and 500 responses carry XFO and CSP", function()
        local nf = get("/nao-existe-xyz", { templates_root = "views" })
        assert.are.equal(404, nf.status)
        assert.are.equal("DENY", nf.headers["X-Frame-Options"])
        assert.is_not_nil(nf.headers["Content-Security-Policy"])

        router_v2.get("/boom", function() error("x") end)
        local err = get("/boom")
        assert.are.equal(500, err.status)
        assert.are.equal("DENY", err.headers["X-Frame-Options"])
        assert.is_not_nil(err.headers["Content-Security-Policy"])
    end)

    it("a user after_request hook returning true cannot prevent the default headers", function()
        hooks.register("after_request", function() return true end, "greedy")
        router_v2.get("/ok", function(req, res) res.body = "ok" end)
        local res = get("/ok")
        assert.are.equal("DENY", res.headers["X-Frame-Options"])
    end)

    it("a failing after_request hook and middleware still yield headers", function()
        hooks.register("after_request", function() error("boom") end, "bad")
        middleware_chain.use("after_request", function() error("mw") end, "badmw")
        router_v2.get("/ok", function(req, res) res.body = "ok" end)
        local res = get("/ok")
        assert.are.equal(500, res.status)
        assert.are.equal("DENY", res.headers["X-Frame-Options"])
    end)
end)

describe("error responses", function()
    before_each(reset)
    after_each(reset)

    it("does not leak upload internals in 4xx bodies", function()
        local res = guaraci.handle_request({
            method = "POST", path = "/", headers = {},
            upload_error = "storage_open_failed:uploads/abc_x.txt: Permission denied"
        }, {})
        assert.are.equal(400, res.status)
        assert.is_nil(res.body:find("Permission", 1, true))
        assert.is_nil(res.body:find("uploads/", 1, true))
        assert.is_not_nil(res.body:find("Invalid upload", 1, true))
    end)

    it("survives a custom error handler that returns garbage", function()
        router_v2.get("/boom", function() error("x") end)
        local res = get("/boom", { error_handler = function() return { status = 500, headers = "nope", body = "b" } end })
        assert.are.equal(500, res.status)
    end)

    it("survives a custom error handler that raises", function()
        router_v2.get("/boom", function() error("x") end)
        local res = get("/boom", { error_handler = function() error("handler broke") end })
        assert.are.equal(500, res.status)
        assert.are.equal("DENY", res.headers["X-Frame-Options"])
    end)
end)

describe("guaraci_random", function()
    local function fresh()
        package.loaded["guaraci_random"] = nil
        return require("guaraci_random")
    end

    it("draws different ids from fresh instances", function()
        assert.is_true(fresh().hex(8) ~= fresh().hex(8))
    end)

    it("falls back to a seeded generator when /dev/urandom is unavailable", function()
        local real_open = io.open
        rawset(io, "open", function(path, ...)
            if path == "/dev/urandom" then return nil end
            return real_open(path, ...)
        end)
        local a = fresh().hex(8)
        local b = fresh().hex(8)
        rawset(io, "open", real_open)
        assert.are.equal(16, #a)
        assert.is_true(a ~= b)
    end)

    it("request ids differ between processes' first draws", function()
        local adapter = require("adapter_cgi")
        local r1 = adapter.request_from_cgi({ REQUEST_METHOD = "GET", PATH_INFO = "/" }, function() return "" end)
        local r2 = adapter.request_from_cgi({ REQUEST_METHOD = "GET", PATH_INFO = "/" }, function() return "" end)
        assert.is_true(r1.context_id ~= r2.context_id)
    end)
end)

describe("persistent rate limiting (CGI)", function()
    before_each(reset)
    after_each(reset)

    local function fresh_limited_request(path)
        -- Simulates a new CGI process: fresh module instances sharing only the store file.
        package.loaded["middleware_ratelimit"] = nil
        package.loaded["ratelimit_store"] = nil
        local limiter = require("middleware_ratelimit")
        middleware_chain.clear(); router_v2.clear()
        middleware_chain.use("before_request", limiter.create({ max_requests = 1, window_seconds = 60,
            store_path = path }), "rl")
        router_v2.get("/", function(_, res) res.body = "ok" end)
        return guaraci.handle_request({ method = "GET", path = "/", remote_addr = "198.51.100.5", headers = {} }, {})
    end

    it("the second request from a fresh instance is 429 through the file store", function()
        local path = os.tmpname()
        os.remove(path)
        local first = fresh_limited_request(path)
        local second = fresh_limited_request(path)
        os.remove(path)
        assert.are.equal(200, first.status)
        assert.are.equal(429, second.status)
        assert.are.equal("DENY", second.headers["X-Frame-Options"])
    end)

    it("file store keys are encoded and expired entries dropped", function()
        local store = require("ratelimit_store").file(os.tmpname())
        local count = store.incr("a\tb\nc", 60, os.time())
        assert.are.equal(1, count)
        assert.are.equal(2, (store.incr("a\tb\nc", 60, os.time())))
        local expired = store.incr("old", 1, os.time() - 100)
        assert.are.equal(1, expired)
        assert.is_nil(store.get("old"))
        os.remove(store.path)
    end)

    it("an injected store is used", function()
        local calls = 0
        local store = { kind = "custom", incr = function() calls = calls + 1; return 99, os.time() + 5 end }
        local limiter = require("middleware_ratelimit").create({ max_requests = 1, store = store })
        local res = { status = 200, headers = {}, body = "" }
        assert.is_true(limiter({ headers = {} }, res, {}) == true)
        assert.are.equal(1, calls)
    end)
end)
