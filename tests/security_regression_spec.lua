local parser = require("parser")
local sandbox = require("sandbox")
local router = require("router")
local db = require("db")
local middleware_csrf = require("middleware_csrf")

local function escape_html(value)
    local str = tostring(value or "")
    str = str:gsub("&", "&amp;")
    str = str:gsub("<", "&lt;")
    str = str:gsub(">", "&gt;")
    str = str:gsub('"', "&quot;")
    str = str:gsub("'", "&#39;")
    return str
end

local function compile_and_render(template, query)
    local compiled, compile_err = parser.compile(template)
    assert(compiled ~= nil, "parser nao compilou: " .. tostring(compile_err))

    local rendered, render_err = sandbox.render_template(compiled, { query = query or {} }, { headers = {} }, {
        escape = escape_html
    })

    return rendered, render_err
end

describe("Security regression suite", function()
    it("CSRF middleware finds the token header and cookie regardless of case " ..
        "(adapter_cgi's CGI env round-trip upper-cases header names)", function()
        local csrf = middleware_csrf.create()
        local token = "0123456789abcdef"

        -- Simulates the exact header casing adapter_cgi.parse_headers produces from
        -- HTTP_X_CSRF_TOKEN / HTTP_COOKIE: upper-cased names with hyphens restored.
        local req = {
            method = "POST",
            headers = { ["X-CSRF-TOKEN"] = token, ["COOKIE"] = "guaraci_csrf_token=" .. token }
        }
        local res = {}
        local blocked = csrf(req, res, {})
        assert.is_false(blocked)
        assert.is_nil(res.status)

        local mismatched_req = {
            method = "POST",
            headers = { ["X-CSRF-TOKEN"] = token, ["COOKIE"] = "guaraci_csrf_token=different0000" }
        }
        local mismatched_res = {}
        local mismatched_blocked = csrf(mismatched_req, mismatched_res, {})
        assert.is_true(mismatched_blocked)
        assert.are.equal(403, mismatched_res.status)
    end)

    it("envelopa expressoes com escape no parser", function()
        local compiled, compile_err = parser.compile("<p><%= Request.query.nome %></p>")
        assert(compiled ~= nil, "parser nao compilou: " .. tostring(compile_err))

        local compiled_str = compiled or ""
        assert.is_not_nil(compiled_str:find(
        '__guaraci_escape_by_context%("HTML_TEXT", tostring%(Request%.query%.nome or ""%)%)'))
    end)

    it("bloqueia acesso a os no sandbox", function()
        local rendered, render_err = sandbox.render_template("return os.execute('id')", { query = {} }, { headers = {} },
            {
                escape = function(v)
                    return tostring(v)
                end
            })

        assert.is_nil(rendered)
        assert.are.equal("Erro interno", render_err)
    end)

    it("bloqueia path traversal no router", function()
        local path, route_err = router.resolve("/%2e%2e/%2e%2e/etc/passwd", { templates_root = "views" })
        assert.is_nil(path)
        assert.are.equal("invalid_path", route_err)
    end)

    it("bloqueia SQL inseguro e permite SQL parametrizado", function()
        local fake_driver = {
            execute = function(sql)
                return { ok = true, sql = sql }
            end
        }

        local ok_set = db.set_driver(fake_driver)
        assert.is_true(ok_set)

        local result, db_err = db.execute("SELECT * FROM users WHERE id = " .. "1", {})
        assert.is_nil(result)
        assert.are.equal("invalid_query", db_err)

        local safe_result, safe_err = db.execute("SELECT * FROM users WHERE id = ?", { 1 })
        assert.is_not_nil(safe_result)
        assert.is_nil(safe_err)
    end)
end)

describe("Template context matrix contract", function()
    it("HTML_TEXT escapa payload de script", function()
        local payload = "<script>alert(1)</script>"
        local rendered, render_err = compile_and_render("<p><%= Request.query.value %></p>", { value = payload })

        assert.is_nil(render_err)
        assert.is_not_nil(rendered)

        assert.is_not_nil(rendered:find("&lt;script&gt;alert%(1%)&lt;/script&gt;"))
        assert.is_nil(rendered:find("<script>", 1, true))
    end)

    it("HTML_ATTR_QUOTED nao quebra atributo com payload malicioso", function()
        local payload = '\"><img src=x onerror=alert(1)>'
        local rendered, render_err = compile_and_render('<input value="<%= Request.query.value %>">', { value = payload })

        assert.is_nil(render_err)
        assert.is_not_nil(rendered)

        assert.is_not_nil(rendered:find('<input value="', 1, true))
        assert.is_nil(rendered:find("<img", 1, true))
    end)

    it("URL_ATTR bloqueia esquema javascript no runtime", function()
        local rendered, render_err = compile_and_render('<a href="<%= Request.query.value %>">link</a>', {
            value = "javascript:alert(1)"
        })

        assert.is_nil(rendered)
        assert.are.equal("Erro interno", render_err)
    end)

    it("JS_STRING fica bloqueado para input nao confiavel no runtime", function()
        local rendered, render_err = compile_and_render('<script>var x="<%= Request.query.value %>"</script>', {
            value = '";alert(1);//'
        })

        assert.is_nil(rendered)
        assert.are.equal("Erro interno", render_err)
    end)

    it("CSS_STRING fica bloqueado para input nao confiavel no runtime", function()
        local rendered, render_err = compile_and_render(
            "<style>.x{background:url('<%= Request.query.value %>')}</style>", {
                value = "');background-image:url(javascript:alert(1));/*"
            })

        assert.is_nil(rendered)
        assert.are.equal("Erro interno", render_err)
    end)

    it("RAW_TEXT_TEMPLATE fica bloqueado para input nao confiavel no runtime", function()
        local rendered, render_err = compile_and_render("<% write(Request.query.value) %>", {
            value = "<img src=x onerror=alert(1)>"
        })

        assert.is_nil(rendered)
        assert.are.equal("Erro interno", render_err)
    end)
end)

describe("Context-aware escaping (Fase 7.1)", function()
    it("HTML_TEXT usa escape generico com caracteres especiais", function()
        local payload = '<a href="#">&nbsp;</a>'
        local rendered, render_err = compile_and_render("<p><%= Request.query.value %></p>", { value = payload })

        assert.is_nil(render_err)
        assert.is_not_nil(rendered)

        assert.is_not_nil(rendered:find("&lt;a href=", 1, true))
        assert.is_not_nil(rendered:find("&amp;nbsp;", 1, true))
        assert.is_not_nil(rendered:find("&lt;/a&gt;", 1, true))
    end)

    it("HTML_ATTR_QUOTED escapa aspas como atributo", function()
        local payload = '"><img src=x onerror=alert(1)>'
        local rendered, render_err = compile_and_render('<input value="<%= Request.query.value %>">', { value = payload })

        assert.is_nil(render_err)
        assert.is_not_nil(rendered)

        assert.is_not_nil(rendered:find('<input value="', 1, true))
        assert.is_not_nil(rendered:find("&quot;&gt;", 1, true))
        assert.is_nil(rendered:find('<img', 1, true))
    end)

    it("URL_ATTR sanitiza e permite http/https/ftp/mailto", function()
        local cases = {
            { input = "http://example.com",      should_pass = true },
            { input = "https://example.com",     should_pass = true },
            { input = "/relative/path",          should_pass = true },
            { input = "mailto:user@example.com", should_pass = true }
        }

        for _, case in ipairs(cases) do
            local rendered, render_err = compile_and_render('<a href="<%= Request.query.value %>">link</a>', {
                value = case.input
            })

            if case.should_pass then
                assert.is_nil(render_err, "URL " .. case.input .. " should pass")
                assert.is_not_nil(rendered)
                assert.is_not_nil(rendered:find("href=", 1, true))
            end
        end
    end)

    it("URL_ATTR bloqueia javascript: e data: schemes", function()
        local bad_cases = { "javascript:alert(1)", "data:text/html,<script>alert(1)</script>" }

        for _, payload in ipairs(bad_cases) do
            local rendered, render_err = compile_and_render('<a href="<%= Request.query.value %>">link</a>', {
                value = payload
            })

            assert.is_nil(rendered, "URL " .. payload .. " should be blocked")
            assert.are.equal("Erro interno", render_err)
        end
    end)
    it("security headers are still injected when hooks/ is absent from cwd", function()
        local hooks = require("hooks")
        local real_open = io.open
        rawset(io, "open", function(path, ...)
            if path == "hooks/security_headers.lua" then return nil, "missing" end
            return real_open(path, ...)
        end)
        hooks.clear()
        local ok, err = pcall(hooks.register_default_hooks)
        rawset(io, "open", real_open)
        assert(ok and err == true, tostring(err))
        local res = { headers = {}, status = 200 }
        hooks.run_stage("after_request", {}, res)
        hooks.clear()
        assert.are.equal("DENY", res.headers["X-Frame-Options"])
        assert.are.equal("nosniff", res.headers["X-Content-Type-Options"])
    end)
    it("default error handler hides details in prod and shows them only with GUARACI_ENV=dev or opts.env", function()
        local guaraci = require("guaraci")
        local tmp = os.tmpname()
        os.remove(tmp)
        os.execute("mkdir -p " .. tmp)
        local fh = assert(io.open(tmp .. "/index.gc", "w"))
        fh:write("<%= 1 %>")
        fh:close()

        local function boom(extra)
            local o = { auto_register_default_hooks = false, templates_root = tmp,
                escape = function() error("SECRET") end }
            for k, v in pairs(extra or {}) do o[k] = v end
            return guaraci.handle_request({ method = "GET", path = "/", headers = {} }, o)
        end

        local real_getenv = os.getenv
        local function with_env(value, fn)
            rawset(os, "getenv", function(name)
                if name == "GUARACI_ENV" then return value end
                return real_getenv(name)
            end)
            local ok, res = pcall(fn)
            rawset(os, "getenv", real_getenv)
            assert(ok, res)
            return res
        end

        local prod = with_env(nil, boom)
        local dev = with_env("dev", boom)
        local dev_opt = with_env(nil, function() return boom({ env = "dev" }) end)
        os.execute("rm -rf " .. tmp)

        assert.are.equal(500, prod.status)
        assert.is_nil(tostring(prod.body):find("details", 1, true))
        assert.is_not_nil(tostring(dev.body):find("details", 1, true))
        assert.is_not_nil(tostring(dev_opt.body):find("details", 1, true))
    end)
    it("explicit routes never match traversal-shaped paths", function()
        local guaraci = require("guaraci")
        local router_v2 = require("router_v2")
        router_v2.clear()
        local hit
        router_v2.get("/files/:name", function() hit = true end)
        local ok_res = guaraci.handle_request({ method = "GET", path = "/files/ok", headers = {} },
            { auto_register_default_hooks = false })
        assert.are.equal(200, ok_res.status)
        hit = false
        for _, path in ipairs({ "/files/..", "/files/%2e%2e", "/files/a%00b", "/files/..\\x" }) do
            local res = guaraci.handle_request({ method = "GET", path = path, headers = {} },
                { auto_register_default_hooks = false })
            assert.are.equal(404, res.status, path)
        end
        router_v2.clear()
        assert.are.equal(false, hit)
    end)

    it("csrf middleware registered via guaraci.use blocks unsafe explicit routes", function()
        local guaraci = require("guaraci")
        local router_v2 = require("router_v2")
        local middleware_chain = require("middleware_chain")
        router_v2.clear()
        middleware_chain.clear()
        local hit = false
        router_v2.post("/danger", function() hit = true end)
        guaraci.use(guaraci.middleware_csrf(), "csrf")
        local res = guaraci.handle_request({ method = "POST", path = "/danger", headers = {} },
            { auto_register_default_hooks = false })
        router_v2.clear()
        middleware_chain.clear()
        assert.are.equal(403, res.status)
        assert.are.equal(false, hit)
    end)
    it("global short-circuit rejections still get security headers", function()
        local guaraci = require("guaraci")
        local router_v2 = require("router_v2")
        local middleware_chain = require("middleware_chain")
        local hooks = require("hooks")
        router_v2.clear(); middleware_chain.clear(); hooks.clear()
        router_v2.post("/danger", function() end)
        guaraci.use(guaraci.middleware_csrf(), "csrf")
        local res = guaraci.handle_request({ method = "POST", path = "/danger", headers = {} }, {})
        router_v2.clear(); middleware_chain.clear(); hooks.clear()
        assert.are.equal(403, res.status)
        assert.are.equal("DENY", res.headers["X-Frame-Options"])
        assert.are.equal("nosniff", res.headers["X-Content-Type-Options"])
    end)

    it("a middleware short-circuit that sets no response fails closed with 403", function()
        local guaraci = require("guaraci")
        local router_v2 = require("router_v2")
        local middleware_chain = require("middleware_chain")
        router_v2.clear(); middleware_chain.clear()
        router_v2.get("/g", function(req, res) res.body = "reached" end)
        local g = guaraci.group("/grp")
        g.use(function() return true end, "silent")
        g.get("/x", function(req, res) res.body = "reached" end)
        local grouped = guaraci.handle_request({ method = "GET", path = "/grp/x", headers = {} },
            { auto_register_default_hooks = false })
        guaraci.use(function() return true end, "silent_global")
        local global = guaraci.handle_request({ method = "GET", path = "/g", headers = {} },
            { auto_register_default_hooks = false })
        router_v2.clear(); middleware_chain.clear()
        assert.are.equal(403, grouped.status)
        assert.are.equal(403, global.status)
        assert.is_true(grouped.body ~= "reached")
    end)
    it("a before_request hook stop without status fails closed: 403 with security headers", function()
        local guaraci = require("guaraci")
        local hooks = require("hooks")
        hooks.clear()
        hooks.register("before_request", function() return true end, "silent_stop")
        local res = guaraci.handle_request({ method = "GET", path = "/", headers = {} }, {})
        hooks.clear()
        assert.are.equal(403, res.status)
        assert.are.equal("DENY", res.headers["X-Frame-Options"])
        assert.are.equal("nosniff", res.headers["X-Content-Type-Options"])
    end)
end)
