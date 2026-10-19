-- guaraci dev: development server. Needs luasocket (optional, CLI only); --container uses Docker instead.
-- Each request reloads app.lua and resets routes/middleware/hooks, mirroring a fresh CGI process.
local util = require("guaraci_cli.util")

local M = {}

local MAX_BODY = 10 * 1024 * 1024
local MAX_HEADER_LINES = 100
local MAX_LINE = 8192
local CONNECTION_DEADLINE = 15 -- seconds for the whole request

local MIME = {
    html = "text/html; charset=utf-8", css = "text/css; charset=utf-8",
    js = "application/javascript; charset=utf-8", json = "application/json; charset=utf-8",
    txt = "text/plain; charset=utf-8", svg = "image/svg+xml", png = "image/png", jpg = "image/jpeg",
    jpeg = "image/jpeg", gif = "image/gif", ico = "image/x-icon", webp = "image/webp", woff2 = "font/woff2"
}

local REASONS = {
    [200] = "OK", [201] = "Created", [204] = "No Content", [301] = "Moved Permanently", [302] = "Found",
    [304] = "Not Modified", [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden",
    [404] = "Not Found", [408] = "Request Timeout", [431] = "Request Header Fields Too Large",
    [501] = "Not Implemented", [405] = "Method Not Allowed", [413] = "Payload Too Large",
    [500] = "Internal Server Error"
}

local function url_decode(value)
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- Reads one line byte by byte with a hard cap, so an endless line is never buffered.
-- Returns line | nil, "closed"|"too_long"|"timeout".
local function read_line(client, deadline)
    local buffer = {}
    local size = 0
    while true do
        if os.time() > deadline then
            return nil, "timeout"
        end
        local ch = client:receive(1)
        if not ch then
            return nil, "closed"
        end
        if ch == "\n" then
            local line = table.concat(buffer)
            return (line:gsub("\r$", ""))
        end
        size = size + 1
        if size > MAX_LINE then
            return nil, "too_long"
        end
        buffer[size] = ch
    end
end

local LINE_ERRORS = {
    closed = { 400, "truncated request" },
    too_long = { 431, "line too long" },
    timeout = { 408, "request took too long" }
}

-- Reads one HTTP/1.x request from `client` (receive(len) -> data|nil, err).
-- Returns { method, target, path, query, headers = {lowercase = value}, body } or nil, status, message.
function M.read_request(client, deadline_seconds)
    local deadline = os.time() + (deadline_seconds or CONNECTION_DEADLINE)
    local line, line_err = read_line(client, deadline)
    if not line then
        local mapped = LINE_ERRORS[line_err]
        return nil, mapped[1], mapped[2]
    end
    local method, target = line:match("^(%u+) (%S+) HTTP/1%.[01]$")
    if not method then
        return nil, 400, "malformed request line"
    end

    local headers = {}
    for _ = 1, MAX_HEADER_LINES do
        local header_line, header_err = read_line(client, deadline)
        if not header_line then
            local mapped = LINE_ERRORS[header_err]
            return nil, mapped[1], mapped[2]
        end
        if header_line == "" then
            break
        end
        local name, value = header_line:match("^([%w%-]+):%s*(.-)%s*$")
        if name then
            headers[name:lower()] = value
        end
    end

    if headers["transfer-encoding"] then
        return nil, 501, "Transfer-Encoding is not supported by guaraci dev"
    end

    local body = ""
    local length = tonumber(headers["content-length"] or "0")
    if length == nil or length < 0 then
        return nil, 400, "invalid content-length"
    end
    if length > MAX_BODY then
        return nil, 413, "body too large"
    end
    if length > 0 then
        local parts, remaining = {}, length
        while remaining > 0 do
            if os.time() > deadline then
                return nil, 408, "request took too long"
            end
            local chunk = client:receive(math.min(remaining, 8192))
            if not chunk then
                return nil, 400, "truncated body"
            end
            parts[#parts + 1] = chunk
            remaining = remaining - #chunk
        end
        body = table.concat(parts)
    end

    local raw_path, query = target:match("^([^?]*)%??(.*)$")
    return {
        method = method, target = target, path = raw_path, query = query, headers = headers, body = body
    }
end

-- Maps a parsed request to the CGI variables adapter_cgi expects.
function M.cgi_env(request, host, port)
    local env = {
        REQUEST_METHOD = request.method,
        PATH_INFO = url_decode(request.path),
        QUERY_STRING = request.query,
        REQUEST_URI = request.target,
        REMOTE_ADDR = request.remote_addr,
        SERVER_NAME = host,
        SERVER_PORT = tostring(port),
        CONTENT_LENGTH = tostring(#request.body)
    }
    for name, value in pairs(request.headers) do
        if name == "content-type" then
            env.CONTENT_TYPE = value
        elseif name ~= "content-length" then
            env["HTTP_" .. name:upper():gsub("%-", "_")] = value
        end
    end
    return env
end

-- Converts the CGI response text ("Status: 200 OK\r\nH: v\r\n\r\nbody") to an HTTP/1.1 response.
function M.cgi_to_http(cgi_output, method)
    local head, body = cgi_output:match("^(.-)\r\n\r\n(.*)$")
    if not head then
        return "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    end
    local status_line = "HTTP/1.1 200 OK"
    local header_lines = {}
    for line in (head .. "\r\n"):gmatch("(.-)\r\n") do
        local status = line:match("^Status:%s*(.+)$")
        if status then
            status_line = "HTTP/1.1 " .. status
        elseif line ~= "" then
            header_lines[#header_lines + 1] = line
        end
    end
    header_lines[#header_lines + 1] = "Connection: close"
    if method == "HEAD" then
        body = ""
    end
    return status_line .. "\r\n" .. table.concat(header_lines, "\r\n") .. "\r\n\r\n" .. body
end

local function simple_response(status, body, content_type)
    return string.format("HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
        status, REASONS[status] or "Error", content_type or "text/plain; charset=utf-8", #body, body)
end

-- Note: public/ is served before app middleware and hooks (no CSRF/rate limit/headers) in dev.
-- Serves a file from public/ for GET/HEAD; returns nil when the path is not a safe existing file.
function M.static_response(request, public_dir)
    if request.method ~= "GET" and request.method ~= "HEAD" then
        return nil
    end
    local decoded = url_decode(request.path)
    if decoded:find("\0", 1, true) or decoded:find("\\", 1, true) then
        return nil, "refused"
    end
    local parts = {}
    for segment in decoded:gmatch("[^/]+") do
        if segment:sub(1, 1) == "." then
            return nil, "refused"
        end
        parts[#parts + 1] = segment
    end
    if #parts == 0 then
        return nil
    end
    local content = util.read_file(public_dir .. "/" .. table.concat(parts, "/"))
    if not content then
        return nil
    end
    local ext = parts[#parts]:match("%.(%w+)$")
    local content_type = MIME[ext and ext:lower() or ""] or "application/octet-stream"
    local body = request.method == "HEAD" and "" or content
    return string.format("HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
        content_type, #content, body)
end

-- Package names present before the first request; anything loaded later is app code and gets reloaded.
local function snapshot_loaded()
    local baseline = {}
    for name in pairs(package.loaded) do
        baseline[name] = true
    end
    return baseline
end

local function reset_app_state(baseline)
    for name in pairs(package.loaded) do
        if not baseline[name] then
            package.loaded[name] = nil
        end
    end
    require("router_v2").clear()
    require("middleware_chain").clear()
    require("hooks").clear()
    require("guaraci").clear_models()
    local introspection = package.loaded["route_introspection"]
    if introspection then
        introspection.clear()
    end
end

-- Runs one request through app.lua + adapter_cgi and returns the HTTP response text.
function M.dispatch(request, config)
    local ok, result = xpcall(function()
        reset_app_state(config.baseline)
        require("guaraci").enable_explorer({ env = "dev" })
        local adapter = require("adapter_cgi")
        local options = dofile(config.app_path) or {}
        options.env = "dev"

        local chunks = {}
        local consumed = false
        adapter.run_cgi({
            env = M.cgi_env(request, config.host, config.port),
            stdin_reader = function(length)
                if consumed then
                    return ""
                end
                consumed = true
                return request.body:sub(1, length)
            end,
            stdout_writer = function(chunk)
                chunks[#chunks + 1] = chunk
            end,
            guaraci_options = options
        })
        return M.cgi_to_http(table.concat(chunks), request.method)
    end, debug.traceback)

    if not ok then
        return simple_response(500, "guaraci dev: error while handling the request\n\n" .. tostring(result) .. "\n")
    end
    return result
end

function M.handle_client(client, config)
    client:settimeout(5)
    local request, status, message = M.read_request(client)
    local response
    if not request then
        response = simple_response(status, message .. "\n")
        config.log("-- " .. status .. " " .. message)
    else
        request.remote_addr = type(client.getpeername) == "function" and client:getpeername() or nil
        local static, refused
        if config.public_dir then
            static, refused = M.static_response(request, config.public_dir)
            if refused then
                config.log("public/ path refused: " .. (request.path:gsub("%c", "?")))
                local audit = package.loaded["guaraci_audit"]
                if audit and audit.log_security then
                    audit.log_security("route_path_refused", { path = request.path, source = "dev_static" })
                end
            end
        end
        if refused then
            response = simple_response(403, "Forbidden\n")
        else
            response = static or M.dispatch(request, config)
        end
        config.log(request.method .. " " .. (request.target:gsub("%c", "?")) .. " -> " .. (response:match("^HTTP/1%.1 (%d+)") or "?"))
    end
    client:send(response)
    client:close()
end

local USAGE = "usage: guaraci dev [--port 8080] [--host 127.0.0.1] [--app app.lua] [--container]\n" ..
    "(dev serves public/ before app middleware and hooks; --container with --host publishes on that address)\n"

function M.run(args, io_streams)
    local out, err = io_streams.stdout, io_streams.stderr
    local parsed, parse_err = util.parse_args(args, {
        flags = { container = true },
        value_flags = { port = true, host = true, app = true }
    })
    if not parsed or #parsed.positional > 0 then
        err:write("guaraci dev: " .. (parse_err or "unexpected argument") .. "\n" .. USAGE)
        return 2
    end

    local port = tonumber(parsed.flags.port or "8080")
    if not port or port < 1 or port > 65535 or port % 1 ~= 0 then
        err:write("guaraci dev: invalid --port\n" .. USAGE)
        return 2
    end

    if parsed.flags.container then
        return require("guaraci_cli.container").run({ port = port, host = parsed.flags.host }, io_streams)
    end

    local app_path = parsed.flags.app or "app.lua"
    if not util.file_exists(app_path) then
        err:write("guaraci dev: " .. app_path .. " not found (run inside a project created by `guaraci new`)\n")
        return 1
    end

    local has_socket, socket = pcall(require, "socket")
    if not has_socket then
        err:write("guaraci dev needs luasocket:  luarocks install luasocket\n" ..
            "or run it inside Docker:         guaraci dev --container\n")
        return 1
    end

    package.path = "./?.lua;" .. package.path
    -- app.lua runs on every request, so keep rate-limit counters in the long-lived server process.
    require("middleware_ratelimit").set_default_store(require("ratelimit_store").memory())
    -- Load the core once so it is part of the baseline that survives reloads.
    require("adapter_cgi")

    local host = parsed.flags.host or "127.0.0.1"
    local server, bind_err = socket.bind(host, port)
    if not server then
        err:write("guaraci dev: cannot listen on " .. host .. ":" .. port .. ": " .. tostring(bind_err) .. "\n")
        return 1
    end

    local config = {
        app_path = app_path,
        host = host,
        port = port,
        baseline = snapshot_loaded(),
        public_dir = util.directory_exists("public") and "public" or nil,
        log = function(line)
            out:write(line .. "\n")
            out:flush()
        end
    }

    if host ~= "127.0.0.1" and host ~= "localhost" then
        err:write("WARNING: listening on " .. host .. " exposes dev error details and tracebacks to the network.\n")
    end
    out:write("Guaraci dev server on http://" .. host .. ":" .. port .. "/  (Ctrl-C to stop)\n")
    out:flush()
    while true do
        local client = server:accept()
        if client then
            local ok, handle_err = pcall(M.handle_client, client, config)
            if not ok then
                config.log("connection error: " .. tostring(handle_err))
                pcall(client.close, client)
            end
        end
    end
end

return M
