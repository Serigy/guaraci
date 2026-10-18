local M = {}

local config = {
    log_path = os.getenv("GUARACI_AUDIT_LOG") or "guaraci_audit.log"
}
local warned_write_failure = false

local SENSITIVE_KEYS = {
    password = true,
    passwd = true,
    pwd = true,
    token = true,
    access_token = true,
    refresh_token = true,
    authorization = true,
    cookie = true,
    secret = true,
    api_key = true,
    apikey = true
}

local function lower_key(key)
    if type(key) ~= "string" then
        return ""
    end
    return string.lower(key)
end

local function is_sensitive_key(key)
    local lk = lower_key(key)
    return SENSITIVE_KEYS[lk] == true
end

local function json_escape(str)
    local s = tostring(str)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\b", "\\b")
    s = s:gsub("\f", "\\f")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function encode_json_value(value, seen)
    local vt = type(value)

    if vt == "nil" then
        return "null"
    end

    if vt == "boolean" or vt == "number" then
        return tostring(value)
    end

    if vt == "string" then
        return '"' .. json_escape(value) .. '"'
    end

    if vt ~= "table" then
        return '"' .. json_escape("<unsupported:" .. vt .. ">") .. '"'
    end

    if seen[value] then
        return '"<cycle>"'
    end

    seen[value] = true

    local is_array = true
    local max_index = 0
    for k, _ in pairs(value) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            is_array = false
            break
        end
        if k > max_index then
            max_index = k
        end
    end

    local out = {}

    if is_array then
        for i = 1, max_index do
            out[#out + 1] = encode_json_value(value[i], seen)
        end
        seen[value] = nil
        return "[" .. table.concat(out, ",") .. "]"
    end

    for k, v in pairs(value) do
        local key = json_escape(tostring(k))
        local encoded = encode_json_value(v, seen)
        out[#out + 1] = '"' .. key .. '":' .. encoded
    end

    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
end

local function sanitize_context(value, depth)
    if depth > 6 then
        return "<max-depth>"
    end

    local vt = type(value)

    if vt ~= "table" then
        if vt == "function" or vt == "thread" or vt == "userdata" then
            return "<" .. vt .. ">"
        end
        return value
    end

    local out = {}
    for k, v in pairs(value) do
        if is_sensitive_key(k) then
            out[k] = "<redacted>"
        else
            out[k] = sanitize_context(v, depth + 1)
        end
    end
    return out
end

local function build_event(level, message, context)
    local safe_context = sanitize_context(context or {}, 0)

    return {
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        level = level,
        message = tostring(message or ""),
        context = safe_context
    }
end

local function write_event(event)
    local serialized = encode_json_value(event, {})
    local line = serialized .. "\n"

    local ok, err = pcall(function()
        local fh = assert(io.open(config.log_path, "a"))
        fh:write(line)
        fh:close()
    end)

    if not ok then
        if not warned_write_failure then
            warned_write_failure = true
            io.stderr:write("guaraci: WARNING: cannot write audit log '" .. tostring(config.log_path) ..
                "': " .. tostring(err) .. "\n")
        end
        return false, err
    end

    return true
end

function M.set_log_path(path)
    if type(path) == "string" and path ~= "" then
        config.log_path = path
    end
end

function M.log_error(message, context)
    local event = build_event("error", message, context)
    local ok = write_event(event)
    if not ok then
        return false
    end
    return true
end

function M.log_security(message, context)
    local event = build_event("security", message, context)
    local ok = write_event(event)
    if not ok then
        return false
    end
    return true
end

return M
