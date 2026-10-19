-- Enables the API explorer: GET /__guaraci/api-docs (fixed) plus the configured HTML page,
-- app.js and style.css routes. Fail-closed in production (ADR-03): when env == "prod" and
-- opts.force_production is not exactly true, M.enable registers nothing and returns early —
-- the 4 routes simply never exist, so they 404 exactly like any other missing route, at zero
-- per-request cost.
local openapi = require("api_explorer.openapi")
local assets = require("api_explorer.assets")
local json_util = require("json_util")
local guaraci_random = require("guaraci_random")

local has_audit, audit = pcall(require, "guaraci_audit")

local M = {}

local API_DOCS_PATH = "/__guaraci/api-docs"

-- router_v2.lua compiles a registered pattern straight into a Lua pattern, only substituting
-- ":param"/"{regex}" placeholders — any other Lua pattern magic character in a literal segment
-- (notably "-", as in "api-docs") is left raw and silently fails to match itself. None of this
-- module's routes use ":param"/"{regex}", so it is always safe to escape the whole literal path
-- before registering it; this is a local workaround and does not modify router_v2.lua itself.
local function escape_pattern_literal(str)
    return (str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- Same cascade as error_handler.current_env, for consistency across modules (architecture §4.1):
-- opts.env -> GUARACI_ENV -> "prod". Never read from query string, cookie or request header.
local function current_env(opts)
    local from_opts = opts and opts.env
    if type(from_opts) == "string" and from_opts ~= "" then
        return string.lower(from_opts)
    end
    local from_os = os.getenv("GUARACI_ENV")
    if type(from_os) == "string" and from_os ~= "" then
        return string.lower(from_os)
    end
    return "prod"
end

local function log_security(message, context)
    if has_audit and audit and type(audit.log_security) == "function" then
        audit.log_security(message, context)
    end
end

local function log_error(message, context)
    if has_audit and audit and type(audit.log_error) == "function" then
        audit.log_error(message, context)
    end
end

local function send(res, status, content_type, body)
    res.status = status
    res.headers = res.headers or {}
    res.headers["Content-Type"] = content_type
    res.body = body
end

local function api_docs_handler(opts)
    return function(req, res)
        local doc, err = openapi.build_document(opts)
        if not doc then
            log_error("openapi_build_failed", { error = tostring(err) })
            send(res, 500, "application/json; charset=utf-8", json_util.encode({
                status = 500,
                error = "openapi_build_failed",
                message = "Internal Error",
                request_id = req.context_id
            }))
            return res
        end
        send(res, 200, "application/json; charset=utf-8", openapi.encode(doc))
        return res
    end
end

-- 32 bytes -> 64 hex characters (architecture §4.3 requires exactly 64; its own prose cites
-- "guaraci_random.hex(16)" for this, but hex(n) takes a byte count and hex(16) only yields 32
-- hex characters per src/guaraci_random.lua — hex(32) is the call that actually satisfies the
-- documented 64-character requirement, which this module follows).
local CSRF_TOKEN_BYTES = 32

local function html_handler()
    return function(_, res)
        local token = guaraci_random.hex(CSRF_TOKEN_BYTES)
        send(res, 200, "text/html; charset=utf-8", assets.html)
        res.headers["Set-Cookie"] = "guaraci_csrf_token=" .. token .. "; Path=/; SameSite=Lax"
        return res
    end
end

local function js_handler()
    return function(_, res)
        send(res, 200, "application/javascript; charset=utf-8", assets.js)
        return res
    end
end

local function css_handler()
    return function(_, res)
        send(res, 200, "text/css; charset=utf-8", assets.css)
        return res
    end
end

-- M.enable(router, opts) -> true | nil, "explorer_disabled_in_production"
function M.enable(router, opts)
    opts = opts or {}
    local env = current_env(opts)
    local forced = opts.force_production == true

    if env == "prod" and not forced then
        return nil, "explorer_disabled_in_production"
    end

    local path = opts.path or "/__guaraci/explorer"

    router.get(escape_pattern_literal(API_DOCS_PATH), api_docs_handler(opts))
    router.get(escape_pattern_literal(path), html_handler())
    router.get(escape_pattern_literal(path .. "/app.js"), js_handler())
    router.get(escape_pattern_literal(path .. "/style.css"), css_handler())

    if env == "prod" and forced then
        log_security("api_explorer_enabled_in_production", { path = path })
    end

    return true
end

return M
