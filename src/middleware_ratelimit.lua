local ratelimit_store = require("ratelimit_store")

local M = {}

local has_audit, audit = pcall(require, "guaraci_audit")

local function log_security(message, context)
    if has_audit and audit and type(audit.log_security) == "function" then
        audit.log_security(message, context)
    end
end

local function header_value(headers, wanted)
    for name, value in pairs(headers) do
        if type(name) == "string" and name:lower() == wanted then
            return value
        end
    end
end

-- Forwarded headers are client-controlled. They count only when a trusted proxy is declared
-- (client_ip_header or the trusted_proxy = true alias) and then only the hop the proxy added:
-- the Nth entry from the right of X-Forwarded-For (trusted_hops, default 1) or the X-Real-IP value.
local function extract_client_ip(req, cfg)
    if cfg.header then
        local headers = req.headers or {}
        local value = header_value(headers, cfg.header)
        if type(value) == "string" then
            if cfg.header == "x-real-ip" then
                local ip = value:match("^%s*(%S+)")
                if ip then
                    return ip
                end
            else
                local tokens = {}
                for token in value:gmatch("[^,]+") do
                    local trimmed = token:match("^%s*(.-)%s*$")
                    if trimmed ~= "" then
                        tokens[#tokens + 1] = trimmed
                    end
                end
                local picked = tokens[#tokens - cfg.hops + 1]
                if picked then
                    return picked
                end
            end
        end
    end

    if type(req.remote_addr) == "string" and req.remote_addr ~= "" then
        return req.remote_addr
    end

    return "unknown"
end

local default_store

-- Process-wide default store (the dev server installs one so limits survive app.lua reloads).
function M.set_default_store(store)
    default_store = store
end

local warned_memory_in_cgi = false

local function djb2(text)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

-- Default location is outside the docroot and per working directory.
local function default_store_path()
    local tmp = os.getenv("TMPDIR")
    if not tmp or tmp == "" then
        tmp = "/tmp"
    end
    return tmp .. "/guaraci_ratelimit_" .. djb2(os.getenv("PWD") or "default") .. ".db"
end

local function resolve_store(opts)
    if opts.store then
        return opts.store
    end
    if default_store then
        return default_store
    end
    local in_cgi = os.getenv("GATEWAY_INTERFACE") ~= nil
    local path = opts.store_path or os.getenv("GUARACI_RATELIMIT_STORE")
    if in_cgi or opts.store_path or os.getenv("GUARACI_RATELIMIT_STORE") then
        return ratelimit_store.file(path or default_store_path())
    end
    return ratelimit_store.memory()
end

local function error_payload(code, message, retryable)
    return string.format('{"code":"%s","message":"%s","retryable":%s}', code, message, retryable and "true" or "false")
end

function M.create(opts)
    opts = opts or {}

    local window_seconds = tonumber(opts.window_seconds) or 60
    local max_requests = tonumber(opts.max_requests) or 100
    local allowed_headers = { ["x-forwarded-for"] = true, ["x-real-ip"] = true }
    if opts.client_ip_header ~= nil and not allowed_headers[tostring(opts.client_ip_header):lower()] then
        error("client_ip_header must be 'x-forwarded-for' or 'x-real-ip'", 2)
    end
    local store = resolve_store(opts)
    if store.kind == "file" and type(store.check) == "function" then
        local ok_check, check_err = store.check()
        if not ok_check then
            log_security("ratelimit_store_write_failed", { phase = "startup", error = tostring(check_err) })
            io.stderr:write("guaraci: WARNING: rate-limit store '" .. tostring(store.path) ..
                "' is not usable (" .. tostring(check_err) .. "); requests will be rejected unless fail_open = true\n")
        end
    end
    local cfg = {
        header = opts.client_ip_header and tostring(opts.client_ip_header):lower()
            or (opts.trusted_proxy == true and "x-forwarded-for" or nil),
        hops = math.max(1, tonumber(opts.trusted_hops) or 1)
    }
    local prefix = tostring(opts.name or "rl") .. ":"

    return function(req, res, context)
        local now = os.time()
        local ip = extract_client_ip(req, cfg)

        if store.kind == "memory" and os.getenv("GATEWAY_INTERFACE") and not warned_memory_in_cgi then
            warned_memory_in_cgi = true
            io.stderr:write("guaraci: WARNING: rate limit uses an in-memory store in a CGI process; " ..
                "counters reset on every request (repeats per request under CGI). " ..
                "Pass a persistent `store` (ratelimit_store.file).\n")
        end

        local ok_incr, count, reset_at = pcall(store.incr, prefix .. ip, window_seconds, now)
        if not ok_incr then
            log_security("ratelimit_store_write_failed", { error = tostring(count) })
            if opts.fail_open == true then
                return false
            end
            -- Fail closed: a limiter that cannot count must not silently allow unlimited requests.
            res.status = 429
            res.headers = res.headers or {}
            res.headers["Content-Type"] = "application/json; charset=utf-8"
            res.headers["Retry-After"] = "5"
            res.body = error_payload("rate_limit_unavailable", "Too many requests", true)
            return true
        end
        local entry = { count = count, reset_at = reset_at }

        if entry.count > max_requests then
            local retry_after = math.max(1, entry.reset_at - now)

            res.status = 429
            res.headers = res.headers or {}
            res.headers["Content-Type"] = "application/json; charset=utf-8"
            res.headers["Retry-After"] = tostring(retry_after)
            res.body = error_payload("rate_limit_exceeded", "Too many requests", true)

            log_security("rate_limit_exceeded", {
                ip = ip,
                retry_after = retry_after,
                count = entry.count
            })

            return true
        end

        return false
    end
end

return M
