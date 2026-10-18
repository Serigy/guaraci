-- guaraci dev: development server. Needs luasocket (optional, CLI only); --container uses Docker instead.
-- Each request reloads app.lua and resets routes/middleware/hooks, mirroring a fresh CGI process.
local util = require("guaraci_cli.util")

local M = {}

local MAX_BODY = 10 * 1024 * 1024
local MAX_HEADER_LINES = 100

local MIME = {
    html = "text/html; charset=utf-8", css = "text/css; charset=utf-8",
    js = "application/javascript; charset=utf-8", json = "application/json; charset=utf-8",
    txt = "text/plain; charset=utf-8", svg = "image/svg+xml", png = "image/png", jpg = "image/jpeg",
    jpeg = "image/jpeg", gif = "image/gif", ico = "image/x-icon", webp = "image/webp", woff2 = "font/woff2"
}

local REASONS = {
    [200] = "OK", [201] = "Created", [204] = "No Content", [301] = "Moved Permanently", [302] = "Found",
    [304] = "Not Modified", [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden",
    [404] = "Not Found", [405] = "Method Not Allowed", [413] = "Payload Too Large",
    [500] = "Internal Server Error"
}

local function url_decode(value)
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- Reads one HTTP/1.x request from `client` (receive(pattern_or_len) -> data|nil, err).
-- Returns { method, target, path, query, headers = {lowercase = value}, body } or nil, status, message.
function M.read_request(client)
    local line = client:receive("*l")
    if not line then
        return nil, 400, "empty request"
    end
    local method, target = line:match("^(%u+) (%S+) HTTP/1%.[01]$")
    if not method then
        return nil, 400, "malformed request line"
    end

    local headers = {}
    for _ = 1, MAX_HEADER_LINES do
        local header_line = client:receive("*l")
        if not header_line then
            return nil, 400, "truncated headers"
        end
        if header_line == "" then
            break
        end
        local name, value = header_line:match("^([%w%-]+):%s*(.-)%s*$")
        if name then
            headers[name:lower()] = value
        end
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
        body = client:receive(length)
        if not body then
            return nil, 400, "truncated body"
        end
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

-- Serves a file from public/ for GET/HEAD; returns nil when the path is not a safe existing file.
function M.static_response(request, public_dir)
    if request.method ~= "GET" and request.method ~= "HEAD" then
        return nil
    end
    local decoded = url_decode(request.path)
    if decoded:find("\0", 1, true) or decoded:find("\\", 1, true) then
        return nil
    end
    local parts = {}
    for segment in decoded:gmatch("[^/]+") do
        if segment:sub(1, 1) == "." then
            return nil
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
end

-- Runs one request through app.lua + adapter_cgi and returns the HTTP response text.
function M.dispatch(request, config)
    reset_app_state(config.baseline)

    local ok, result = xpcall(function()
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
        response = (config.public_dir and M.static_response(request, config.public_dir))
            or M.dispatch(request, config)
        config.log(request.method .. " " .. request.target .. " -> " .. (response:match("^HTTP/1%.1 (%d+)") or "?"))
    end
    client:send(response)
    client:close()
end

local USAGE = "usage: guaraci dev [--port 8080] [--host 127.0.0.1] [--app app.lua] [--container]\n"

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
        return require("guaraci_cli.container").run({ port = port, app = parsed.flags.app }, io_streams)
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
