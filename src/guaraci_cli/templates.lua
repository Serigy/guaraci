-- File templates for `guaraci new`. {{name}} is replaced with the project name.
local M = {}

M.app_lua = [==[
local guaraci = require("guaraci")

-- Explicit routes: GET /hello/:name
guaraci.router().get("/hello/:name", function(req, res, ctx)
    res.body = "<h1>Ola, " .. guaraci.escape_html(ctx.params.name) .. "!</h1>"
end)

-- Anything else falls back to views/*.gc (views/index.gc serves "/").
return {
    templates_root = "views"
}
]==]

M.index_gc = [==[
<h1>{{name}}</h1>
<p>Ola, <%= Request.query.nome or "visitante" %>!</p>
]==]

M.app_cgi = [==[
#!/usr/bin/env lua5.4
-- CGI entrypoint. Serve with any CGI-capable server (see `guaraci dev`).
local root = (arg and arg[0] or ""):match("^(.*)/cgi%-bin/[^/]*$") or "."
package.path = root .. "/?.lua;" .. package.path

local adapter = require("adapter_cgi")
local options = dofile(root .. "/app.lua") or {}
options.templates_root = root .. "/" .. (options.templates_root or "views")

adapter.run_cgi({ guaraci_options = options })
]==]

M.index_spec = [==[
package.path = "./?.lua;" .. package.path

local guaraci = require("guaraci")
local router_v2 = require("router_v2")

local options

local function get(path, query)
    return guaraci.handle_request({ method = "GET", path = path, query = query or {}, headers = {} }, options)
end

describe("{{name}}", function()
    -- Specs share one process, so another spec file may have cleared the router.
    -- Reloading app.lua here keeps this file self-sufficient whatever ran before.
    before_each(function()
        router_v2.clear()
        guaraci.clear_models()
        options = dofile("app.lua")
    end)

    it("renders the index template", function()
        local res = get("/", { nome = "Spec" })
        assert.are.equal(200, res.status)
        assert.is_not_nil(res.body:find("Spec", 1, true))
    end)

    it("escapes explicit route params", function()
        local res = get("/hello/<b>")
        assert.are.equal(200, res.status)
        assert.is_nil(res.body:find("<b>", 1, true))
    end)

    it("sends security headers", function()
        assert.are.equal("DENY", get("/").headers["X-Frame-Options"])
    end)
end)
]==]

M.paseo_json = [==[
{
  "scripts": {
    "dev": "guaraci dev",
    "test": "guaraci test"
  }
}
]==]

M.gitignore = [==[
guaraci_audit.log
logs/
uploads/
*.tmp
]==]

M.dockerfile = [==[
FROM alpine:3.20
RUN apk add --no-cache lua5.4 lighttpd
WORKDIR /app
EXPOSE 8080
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"]
]==]

M.readme = [==[
# {{name}}

Guaraci app.

    guaraci dev            # dev server on http://localhost:8080 (needs luasocket)
    guaraci dev --container  # same, inside Docker (alpine + lighttpd + CGI)
    guaraci test           # run spec/*_spec.lua
    guaraci check views/*.gc

Layout: `app.lua` (routes), `views/*.gc` (templates), `hooks/` (request hooks),
`cgi-bin/app.cgi` (CGI entrypoint for production servers).

Note: in `guaraci dev`, files under `public/` are served before app middleware and hooks.
]==]

return M
