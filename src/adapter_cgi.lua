local guaraci = require("guaraci")
local multipart = require("multipart")
local file_manager = require("file_manager")

local has_audit, audit = pcall(require, "guaraci_audit")

local M = {}

local function generate_request_id()
    return "req-" .. require("guaraci_random").hex(8)
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

local function urldecode(value)
    if type(value) ~= "string" then
        return ""
    end

    local decoded = value:gsub("+", " ")
    decoded = decoded:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded
end

local function parse_query(query_string)
    local out = {}
    if type(query_string) ~= "string" or query_string == "" then
        return out
    end

    for pair in string.gmatch(query_string, "[^&]+") do
        local eq = string.find(pair, "=", 1, true)
        local key
        local value

        if eq then
            key = string.sub(pair, 1, eq - 1)
            value = string.sub(pair, eq + 1)
        else
            key = pair
            value = ""
        end

        key = urldecode(key)
        value = urldecode(value)

        if key ~= "" then
            out[key] = value
        end
    end

    return out
end

local function parse_headers(env)
    local headers = {}

    for k, v in pairs(env) do
        if type(k) == "string" and k:sub(1, 5) == "HTTP_" then
            local name = k:sub(6):gsub("_", "-")
            headers[name] = tostring(v)
        end
    end

    if env.CONTENT_TYPE then
        headers["Content-Type"] = tostring(env.CONTENT_TYPE)
    end

    if env.CONTENT_LENGTH then
        headers["Content-Length"] = tostring(env.CONTENT_LENGTH)
    end

    return headers
end

local function read_body(env, stdin_reader)
    local content_length = tonumber(env.CONTENT_LENGTH) or 0
    if content_length <= 0 then
        return ""
    end

    local ok, body_or_err = pcall(function()
        return stdin_reader(content_length)
    end)

    if not ok then
        log_error("Falha ao ler body no adapter CGI", { error = tostring(body_or_err) })
        return ""
    end

    if type(body_or_err) ~= "string" then
        return ""
    end

    return body_or_err
end

-- Client-supplied ids key uploads and contexts and are echoed in errors: accept only a safe shape.
-- "@" is allowed because Apache mod_unique_id values use it (alphabet A-Za-z0-9@-).
local function is_valid_request_id(value)
    return type(value) == "string" and #value >= 8 and #value <= 64 and value:match("^[%w%-_@]+$") ~= nil
end

function M.request_from_cgi(env, stdin_reader)
    env = env or {}
    stdin_reader = stdin_reader or function(len)
        return io.read(len)
    end

    local method = env.REQUEST_METHOD or "GET"
    local path = env.PATH_INFO or env.REQUEST_URI or "/"
    if type(path) == "string" then
        path = path:match("^[^?]*") or "/"
    else
        path = "/"
    end

    local headers = parse_headers(env)
    local context_id
    for _, key in ipairs({ "HTTP_X_REQUEST_ID", "REQUEST_ID", "UNIQUE_ID" }) do
        local candidate = env[key]
        if is_valid_request_id(candidate) then
            context_id = candidate
            break
        end
    end
    context_id = context_id or generate_request_id()
    local query = parse_query(env.QUERY_STRING or "")
    local body = read_body(env, stdin_reader)

    local form_data = {}
    local files = {}
    local body_table = nil
    local upload_error = nil

    local content_type = headers["Content-Type"]
    if multipart.is_multipart(content_type) then
        local parsed, parse_err = multipart.parse(body, content_type)
        if not parsed then
            upload_error = parse_err
        else
            form_data = parsed.form_data or {}
            body_table = form_data

            local stored, store_err = file_manager.process_files(parsed.files or {}, {
                request_id = context_id
            })
            if not stored then
                upload_error = store_err
            else
                files = stored
            end
        end
    elseif type(content_type) == "string" and string.lower(content_type):find("application/x%-www%-form%-urlencoded", 1, false) then
        form_data = parse_query(body)
        body_table = form_data
    end

    return {
        method = method,
        path = path,
        query = query,
        body = body,
        headers = headers,
        form_data = form_data,
        files = files,
        body_table = body_table,
        context_id = context_id,
        remote_addr = type(env.REMOTE_ADDR) == "string" and env.REMOTE_ADDR or nil,
        upload_error = upload_error
    }
end

local function status_text(status)
    local map = {
        [200] = "OK",
        [400] = "Bad Request",
        [401] = "Unauthorized",
        [403] = "Forbidden",
        [404] = "Not Found",
        [500] = "Internal Server Error"
    }
    return map[status] or "OK"
end

-- RFC 7230 token for names; values may not carry CR, LF or NUL (response splitting).
local function valid_header(name, value)
    local n, v = tostring(name), tostring(value)
    return n:match("^[%w!#$%%&'*+.^_`|~-]+$") ~= nil and not v:find("[\r\n%z]")
end

function M.response_to_cgi(res, stdout_writer)
    stdout_writer = stdout_writer or function(chunk)
        io.write(chunk)
    end

    local safe = res or {}
    local status = tonumber(safe.status) or 200
    local headers = type(safe.headers) == "table" and safe.headers or {}
    local body = safe.body == nil and "" or tostring(safe.body)

    if headers["Content-Type"] == nil then
        headers["Content-Type"] = "text/html; charset=utf-8"
    end

    for k, v in pairs(headers) do
        if not valid_header(k, v) then
            log_security("response_header_rejected", { header = tostring(k):sub(1, 64) })
            status = 500
            headers = { ["Content-Type"] = "text/plain; charset=utf-8" }
            body = "Internal Error"
            break
        end
    end

    headers["Content-Length"] = tostring(#body)

    stdout_writer("Status: " .. tostring(status) .. " " .. status_text(status) .. "\r\n")
    for k, v in pairs(headers) do
        stdout_writer(tostring(k) .. ": " .. tostring(v) .. "\r\n")
    end
    stdout_writer("\r\n")
    stdout_writer(body)
end

local CGI_VARS = {
    "REQUEST_METHOD", "PATH_INFO", "REQUEST_URI", "QUERY_STRING",
    "CONTENT_TYPE", "CONTENT_LENGTH", "REMOTE_ADDR", "SERVER_NAME",
    "SERVER_PORT", "SCRIPT_NAME", "REQUEST_ID", "UNIQUE_ID", "HTTPS"
}

-- Pure Lua cannot enumerate the environment, so only these headers are read.
local ALLOWED_HEADERS = {
    "Accept", "Cookie", "Authorization", "Origin", "Host", "Referer",
    "User-Agent", "X-Requested-With", "X-CSRF-Token", "X-Request-Id",
    "X-Tenant-Id", "X-Forwarded-For", "X-Forwarded-Proto",
    "X-Forwarded-Host", "X-Forwarded-Port", "X-Forwarded-Prefix"
}

local function header_env_name(header)
    return "HTTP_" .. header:upper():gsub("-", "_")
end

-- Builds a CGI env table from the process environment (opts.getenv overrides os.getenv).
function M.env_from_os(opts)
    opts = opts or {}
    local getenv = opts.getenv or os.getenv
    local env = {}

    for _, name in ipairs(CGI_VARS) do
        local value = getenv(name)
        if value ~= nil then
            env[name] = value
        end
    end

    local function add_header(header)
        if type(header) ~= "string" or header == "" then
            return
        end
        local name = header_env_name(header)
        local value = getenv(name)
        if value ~= nil then
            env[name] = value
        end
    end

    for _, header in ipairs(ALLOWED_HEADERS) do
        add_header(header)
    end
    for _, header in ipairs(opts.extra_headers or {}) do
        add_header(header)
    end

    return env
end

function M.run_cgi(opts)
    opts = opts or {}

    local req = M.request_from_cgi(opts.env or M.env_from_os(opts), opts.stdin_reader)
    local res = guaraci.handle_request(req, opts.guaraci_options)
    M.response_to_cgi(res, opts.stdout_writer)
    return true
end

return M
