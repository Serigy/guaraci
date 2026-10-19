local guaraci = require("guaraci")
local router_v2 = require("router_v2")
local audit = require("guaraci_audit")
local guaraci_random = require("guaraci_random")

local function request(method, path, opts)
    local o = { auto_register_default_hooks = false, env = "dev" }
    for k, v in pairs(opts or {}) do o[k] = v end
    return guaraci.handle_request({ method = method, path = path, headers = {} }, o)
end

describe("api_explorer.explorer / guaraci.enable_explorer", function()
    before_each(function()
        router_v2.clear()
    end)

    after_each(function()
        router_v2.clear()
    end)

    it("makes the docs and explorer endpoints reachable in dev", function()
        local ok = guaraci.enable_explorer({ env = "dev" })
        assert.is_true(ok)

        local docs = request("GET", "/__guaraci/api-docs")
        assert.are.equal(200, docs.status)
        assert.are.equal("application/json; charset=utf-8", docs.headers["Content-Type"])

        local page = request("GET", "/__guaraci/explorer")
        assert.are.equal(200, page.status)
        assert.are.equal("text/html; charset=utf-8", page.headers["Content-Type"])

        local js = request("GET", "/__guaraci/explorer/app.js")
        assert.are.equal(200, js.status)
        assert.are.equal("application/javascript; charset=utf-8", js.headers["Content-Type"])

        local css = request("GET", "/__guaraci/explorer/style.css")
        assert.are.equal(200, css.status)
        assert.are.equal("text/css; charset=utf-8", css.headers["Content-Type"])
    end)

    it("a custom path changes only the page/asset routes, never api-docs", function()
        guaraci.enable_explorer({ env = "dev", path = "/custom-explorer" })

        assert.are.equal(200, (request("GET", "/__guaraci/api-docs")).status)
        assert.are.equal(200, (request("GET", "/custom-explorer")).status)
        assert.are.equal(200, (request("GET", "/custom-explorer/app.js")).status)
        assert.are.equal(200, (request("GET", "/custom-explorer/style.css")).status)

        -- The default page path was never registered under a custom path.
        assert.are.equal(404, (request("GET", "/__guaraci/explorer")).status)
    end)

    it("is disabled in production without force_production, 404 just like any missing route", function()
        local ok, err = guaraci.enable_explorer({ env = "prod" })
        assert.is_nil(ok)
        assert.are.equal("explorer_disabled_in_production", err)

        local baseline = request("GET", "/this/route/was/never/registered")
        -- request_id is random per request; strip it before comparing bodies byte-for-byte.
        local function without_request_id(body)
            return (body:gsub('"request_id":"[^"]*"', '"request_id":""'))
        end

        for _, path in ipairs({
            "/__guaraci/api-docs", "/__guaraci/explorer",
            "/__guaraci/explorer/app.js", "/__guaraci/explorer/style.css"
        }) do
            local res = request("GET", path)
            assert.are.equal(baseline.status, res.status)
            assert.are.equal(without_request_id(baseline.body), without_request_id(res.body))
        end
    end)

    it("never reads force_production from a query string, cookie or header", function()
        local ok = guaraci.enable_explorer({
            env = "prod",
            query = { force_production = "true" },
            headers = { ["X-Force-Production"] = "true" }
        })
        assert.is_nil(ok)
    end)

    it("force_production=true in prod enables all routes and audits the event once", function()
        local default_log_path = os.getenv("GUARACI_AUDIT_LOG") or "guaraci_audit.log"
        local log_path = "tests/tmp_explorer_audit_" .. guaraci_random.hex(8) .. ".log"
        audit.set_log_path(log_path)

        local ok = guaraci.enable_explorer({ env = "prod", force_production = true })

        assert.is_true(ok)
        assert.are.equal(200, (request("GET", "/__guaraci/api-docs")).status)
        assert.are.equal(200, (request("GET", "/__guaraci/explorer")).status)
        assert.are.equal(200, (request("GET", "/__guaraci/explorer/app.js")).status)
        assert.are.equal(200, (request("GET", "/__guaraci/explorer/style.css")).status)

        local fh = io.open(log_path, "r")
        local content = fh and fh:read("*a") or ""
        if fh then fh:close() end
        os.remove(log_path)
        audit.set_log_path(default_log_path)

        assert.is_not_nil(content:find('"api_explorer_enabled_in_production"', 1, true))
        assert.is_not_nil(content:find('"path":"/__guaraci/explorer"', 1, true))
        local _, occurrences = content:gsub("api_explorer_enabled_in_production", "")
        assert.are.equal(1, occurrences)
    end)

    it("rebuilding dev state twice (simulated reload) does not duplicate routes", function()
        router_v2.clear()
        guaraci.enable_explorer({ env = "dev" })
        local after_first = router_v2.count()

        router_v2.clear()
        guaraci.enable_explorer({ env = "dev" })
        local after_second = router_v2.count()

        assert.are.equal(after_first, after_second)
        assert.are.equal(200, (request("GET", "/__guaraci/api-docs")).status)
    end)

    it("returns a 500 standard-error body and audits openapi_build_failed when the build breaks", function()
        local route_introspection = require("route_introspection")
        local original_all = route_introspection.all
        route_introspection.all = function() error("boom") end

        local default_log_path = os.getenv("GUARACI_AUDIT_LOG") or "guaraci_audit.log"
        local log_path = "tests/tmp_explorer_audit_fail_" .. guaraci_random.hex(8) .. ".log"
        audit.set_log_path(log_path)

        guaraci.enable_explorer({ env = "dev" })
        local res = request("GET", "/__guaraci/api-docs")

        route_introspection.all = original_all

        local fh = io.open(log_path, "r")
        local content = fh and fh:read("*a") or ""
        if fh then fh:close() end
        os.remove(log_path)
        audit.set_log_path(default_log_path)

        assert.are.equal(500, res.status)
        assert.are.equal("application/json; charset=utf-8", res.headers["Content-Type"])
        assert.is_not_nil(res.body:find('"error":"openapi_build_failed"', 1, true))
        assert.is_not_nil(content:find('"openapi_build_failed"', 1, true))
    end)

    it("serves the real HTML/JS/CSS asset bodies, not empty placeholders", function()
        guaraci.enable_explorer({ env = "dev" })
        local assets = require("api_explorer.assets")
        assert.are.equal(assets.html, (request("GET", "/__guaraci/explorer")).body)
        assert.are.equal(assets.js, (request("GET", "/__guaraci/explorer/app.js")).body)
        assert.are.equal(assets.css, (request("GET", "/__guaraci/explorer/style.css")).body)
    end)

    it("sets the CSRF cookie on the HTML page response with the required attributes", function()
        guaraci.enable_explorer({ env = "dev" })
        local res = request("GET", "/__guaraci/explorer")
        local cookie = res.headers["Set-Cookie"]
        assert.is_not_nil(cookie)
        local token = cookie:match("^guaraci_csrf_token=(%x+);")
        assert.is_not_nil(token)
        assert.are.equal(64, #token)
        assert.is_not_nil(cookie:find("Path=/", 1, true))
        assert.is_not_nil(cookie:find("SameSite=Lax", 1, true))
        assert.is_nil(cookie:find("HttpOnly", 1, true))
    end)

    it("issues a fresh CSRF token on every page request", function()
        guaraci.enable_explorer({ env = "dev" })
        local first = (request("GET", "/__guaraci/explorer")).headers["Set-Cookie"]
        local second = (request("GET", "/__guaraci/explorer")).headers["Set-Cookie"]
        assert.is_true(first ~= second)
    end)
end)

describe("api_explorer.assets", function()
    local assets = require("api_explorer.assets")

    it("stays under the 50 KiB combined budget", function()
        assert.is_true(#assets.html + #assets.css + #assets.js < 50 * 1024)
    end)

    it("the HTML has exactly one script tag, same-origin, with no inline content", function()
        local count = 0
        for _ in assets.html:gmatch("<script") do
            count = count + 1
        end
        assert.are.equal(1, count)
        assert.is_not_nil(assets.html:find('<script src="/__guaraci/explorer/app.js"></script>', 1, true))
        -- No inline script body: the only "<script" occurrence is immediately self-closing.
        assert.is_nil(assets.html:find("<script>", 1, true))
    end)

    it("references no external origin and no CDN/framework", function()
        for _, source in ipairs({ assets.html, assets.css, assets.js }) do
            assert.is_nil(source:find("http://", 1, true))
            assert.is_nil(source:find("https://", 1, true))
            assert.is_nil(source:find("//cdn", 1, true))
        end
    end)

    it("contains no inline event handlers, eval, or new Function", function()
        assert.is_nil(assets.html:find("onclick", 1, true))
        assert.is_nil(assets.html:find("onload", 1, true))
        assert.is_nil(assets.html:find(" style=", 1, true))
        for _, source in ipairs({ assets.html, assets.js }) do
            assert.is_nil(source:find("eval(", 1, true))
            assert.is_nil(source:find("new Function", 1, true))
        end
    end)

    it("renders catalog data via textContent/createElement, never innerHTML", function()
        assert.is_nil(assets.js:find("innerHTML", 1, true))
        assert.is_not_nil(assets.js:find("textContent", 1, true))
        assert.is_not_nil(assets.js:find("createElement", 1, true))
    end)

    it("omits the CSRF header for GET/HEAD and sends it for POST/PUT/PATCH/DELETE", function()
        assert.is_not_nil(assets.js:find("UNSAFE_METHODS", 1, true))
        assert.is_not_nil(assets.js:find('POST: true, PUT: true, PATCH: true, DELETE: true', 1, true))
        assert.is_not_nil(assets.js:find('headers["X-CSRF-Token"]', 1, true))
        assert.is_not_nil(assets.js:find("guaraci_csrf_token", 1, true))
    end)

    it("validates JSON bodies client-side before sending", function()
        assert.is_not_nil(assets.js:find("JSON.parse", 1, true))
        assert.is_not_nil(assets.js:find("Invalid JSON body", 1, true))
    end)

    it("renders status, every header, and pretty-printed JSON or raw text", function()
        assert.is_not_nil(assets.js:find("res.headers", 1, true))
        assert.is_not_nil(assets.js:find("headers.forEach", 1, true))
        assert.is_not_nil(assets.js:find("JSON.stringify(JSON.parse(bodyText), null, 2)", 1, true))
        assert.is_not_nil(assets.js:find("renderNetworkError", 1, true))
        assert.is_not_nil(assets.js:find("status-error", 1, true))
    end)

    it("builds same-origin requests only, encoding path/query values", function()
        assert.is_not_nil(assets.js:find("encodeURIComponent", 1, true))
        assert.is_nil(assets.js:find("http://", 1, true))
        assert.is_nil(assets.js:find("https://", 1, true))
    end)

    it("transmits the validated JSON object as a form-encoded body the server can parse", function()
        -- adapter_cgi.lua only decodes application/x-www-form-urlencoded (and multipart)
        -- bodies into req.body_table; there is no JSON request-body decoder anywhere in the
        -- framework, so sending Content-Type: application/json would silently never reach
        -- auto_crud's validation/handler at all. The JSON editor still validates the
        -- payload as a JSON object client-side (JSON.parse + an is-a-plain-object check)
        -- before it is form-encoded for transmission.
        assert.is_not_nil(assets.js:find('"application/x-www-form-urlencoded"', 1, true))
        assert.is_nil(assets.js:find('"application/json"', 1, true))
        assert.is_not_nil(assets.js:find("JSON body must be an object", 1, true))
    end)
end)

describe("explorer request pipeline (E3-S2): CSRF, validation and tenant behavior over handle_request", function()
    local middleware_chain = require("middleware_chain")

    local function raw_request(method, path, opts)
        opts = opts or {}
        return guaraci.handle_request({
            method = method, path = path, headers = opts.headers, body_table = opts.body_table
        }, { auto_register_default_hooks = false, env = "dev" })
    end

    before_each(function()
        router_v2.clear()
        middleware_chain.clear()
    end)

    after_each(function()
        router_v2.clear()
        middleware_chain.clear()
    end)

    it("rejects a mutating request with an absent or mismatched CSRF token, accepts a matching one", function()
        router_v2.post("/csrf_check", function(req, res) res.body = "ok"; return res end)
        guaraci.use(guaraci.middleware_csrf(), "csrf")

        local absent = raw_request("POST", "/csrf_check", { body_table = {} })
        assert.are.equal(403, absent.status)
        assert.is_not_nil(absent.body:find("csrf_token_invalid", 1, true))

        local mismatched = raw_request("POST", "/csrf_check", {
            headers = { ["X-CSRF-Token"] = "0000000000000000", Cookie = "guaraci_csrf_token=1111111111111111" },
            body_table = {}
        })
        assert.are.equal(403, mismatched.status)

        local token = "abcdefabcdefabcdefabcdefabcdefab"
        local matching = raw_request("POST", "/csrf_check", {
            headers = { ["X-CSRF-Token"] = token, Cookie = "guaraci_csrf_token=" .. token },
            body_table = {}
        })
        assert.are.equal(200, matching.status)
        assert.are.equal("ok", matching.body)
    end)

    it("rejects a mutation missing a required field with 400 and never calls the database", function()
        local db = require("db")
        local dataware = require("dataware")
        local auto_crud = require("auto_crud")
        local calls = {}

        dataware.clear()
        db.set_driver({
            execute_prepared = function(sql, params)
                calls[#calls + 1] = { sql = sql, params = params }
                return { { id = 1 } }
            end
        })

        local model = dataware.model("ExplorerWidget"):table("explorer_widgets")
        model:schema({ title = { type = "string", required = true } })

        local group = guaraci.group("/explorer_widgets")
        group.use(function(req, res)
            local method = string.upper(tostring(req.method or "GET"))
            if method ~= "POST" and method ~= "PUT" then
                return false
            end
            local payload = type(req.body_table) == "table" and req.body_table or {}
            if payload.title == nil or payload.title == "" then
                res.status = 400
                res.headers = res.headers or {}
                res.headers["Content-Type"] = "application/json; charset=utf-8"
                res.body = '{"code":"invalid_request","message":"Field title is required","retryable":false}'
                return true
            end
            return false
        end, "explorer_widgets_validate", 60)
        auto_crud.generate(model, group, { base_path = "" })

        local res = raw_request("POST", "/explorer_widgets", {
            headers = { ["X-Tenant-Id"] = "tenant-a" }, body_table = {}
        })

        assert.are.equal(400, res.status)
        assert.are.equal(0, #calls)
    end)

    it("does not block a --no-tenant request for lacking a tenant header", function()
        router_v2.get("/no_tenant_check", function(req, res)
            res.status = 200
            res.body = "ok"
            return res
        end)
        local res = raw_request("GET", "/no_tenant_check", {})
        assert.are.equal(200, res.status)
    end)

    it("blocks a tenant-required request lacking X-Tenant-Id with 403 tenant_required", function()
        local db = require("db")
        local dataware = require("dataware")
        local auto_crud = require("auto_crud")
        dataware.clear()
        db.set_driver({ execute_prepared = function() return { { total = 0 } } end })

        local model = dataware.model("ExplorerTenanted"):table("explorer_tenanted"):tenant("tenant_id")
        local group = guaraci.group("/explorer_tenanted")
        auto_crud.generate(model, group, { base_path = "" })

        local res = raw_request("GET", "/explorer_tenanted", {})
        assert.are.equal(403, res.status)
        assert.is_not_nil(res.body:find("Tenant context required", 1, true))
    end)
end)
