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
        assert.are.equal(500, res.status)
        assert.is_nil(res.body:find("Permission", 1, true))
        assert.is_nil(res.body:find("uploads/", 1, true))
        local client = guaraci.handle_request({ method = "POST", path = "/", headers = {},
            upload_error = "invalid_multipart: bad boundary at /tmp/x" }, {})
        assert.are.equal(400, client.status)
        assert.is_nil(client.body:find("/tmp/x", 1, true))
        assert.is_not_nil(client.body:find("Invalid upload", 1, true))
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

describe("re-check fixes", function()
    it("storage failures are 500, client upload errors stay 400", function()
        local function status(code)
            return guaraci.handle_request({ method = "POST", path = "/", headers = {}, upload_error = code }, {}).status
        end
        assert.are.equal(500, status("storage_open_failed:uploads/x: Permission denied"))
        assert.are.equal(400, status("invalid_multipart"))
        assert.are.equal(413, status("file_too_large"))
    end)

    it("a failed second put removes the first stored file", function()
        local file_manager = require("file_manager")
        local deleted = {}
        local puts = 0
        local original = file_manager.get_registry()
        file_manager.set_registry({
            put = function()
                puts = puts + 1
                if puts == 2 then return nil, "storage_write_failed:disk full" end
                return "id" .. puts, { filename = "f", content_type = "text/plain", size = 1, path = "p" }
            end,
            delete = function(_, id) deleted[#deleted + 1] = id end
        })
        local files = {
            { field = "a", filename = "a.txt", content_type = "text/plain", content = "x", size = 1 },
            { field = "b", filename = "b.txt", content_type = "text/plain", content = "y", size = 1 }
        }
        local stored, err = file_manager.process_files(files, { request_id = "req-partial-1" })
        file_manager.set_registry(original)
        assert.is_nil(stored)
        assert.is_not_nil(err)
        assert.are.equal("id1", deleted[1])
    end)

    it("audit JSON escapes every control byte", function()
        local path = os.tmpname()
        package.loaded["guaraci_audit"] = nil
        local audit = require("guaraci_audit")
        audit.set_log_path(path)
        audit.log_security("ctl\1\31\127x", {})
        local fh = io.open(path, "r")
        local line = fh:read("a")
        fh:close()
        os.remove(path)
        package.loaded["guaraci_audit"] = nil
        assert.is_not_nil(line:find("\\u0001", 1, true))
        assert.is_nil(line:find("[%z\1-\8\11\12\14-\31]"))
    end)
end)

describe("rate-limit store failures", function()
    local ratelimit = require("middleware_ratelimit")
    local ratelimit_store = require("ratelimit_store")
    local function call(limiter)
        local res = { status = 200, headers = {}, body = "" }
        local short = limiter({ remote_addr = "198.51.100.9", headers = {} }, res, {})
        return short, res
    end

    it("fails closed (429) when the store cannot be updated, open with fail_open", function()
        local broken = { kind = "custom", incr = function() error("disk full", 0) end }
        local short, res = call(ratelimit.create({ store = broken }))
        assert.is_true(short == true)
        assert.are.equal(429, res.status)
        local open_short = call(ratelimit.create({ store = broken, fail_open = true }))
        assert.is_true(open_short == false)
    end)

    it("a failed write (ENOSPC) never renames a truncated file over the store", function()
        local path = os.tmpname()
        local store = ratelimit_store.file(path)
        assert.are.equal(1, (store.incr("k", 60, os.time())))
        local before = io.open(path, "r"):read("a")
        local real_open = io.open
        rawset(io, "open", function(p, mode)
            if mode == "w" and p:find(path .. ".tmp", 1, true) then
                return { write = function() return nil, "No space left on device" end,
                    close = function() return true end }
            end
            return real_open(p, mode)
        end)
        local ok = pcall(store.incr, "k", 60, os.time())
        rawset(io, "open", real_open)
        local after = io.open(path, "r"):read("a")
        os.remove(path)
        assert.is_false(ok)
        assert.are.equal(before, after)
    end)

    it("a corrupt store file is a store failure, not an empty store", function()
        local path = os.tmpname()
        local fh = io.open(path, "w")
        fh:write("this is not a counter file\n")
        fh:close()
        local short, res = call(ratelimit.create({ store_path = path }))
        os.remove(path)
        assert.is_true(short == true)
        assert.are.equal(429, res.status)
    end)

    it("an unwritable store path is reported once at startup", function()
        local seen = {}
        local real_stderr = io.stderr
        rawset(io, "stderr", { write = function(_, ...) seen[#seen + 1] = table.concat({ ... }) end })
        ratelimit.create({ store_path = "/nonexistent-dir-xyz/rl.db" })
        rawset(io, "stderr", real_stderr)
        assert.are.equal(1, #seen)
        assert.is_not_nil(seen[1]:find("not usable", 1, true))
    end)

    it("rejects an unknown client_ip_header", function()
        assert.is_false((pcall(ratelimit.create, { client_ip_header = "x-forwared-for" })))
        assert.is_true((pcall(ratelimit.create, { client_ip_header = "X-Real-IP" })))
    end)
end)
