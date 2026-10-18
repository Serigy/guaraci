local M = {}

local has_audit, audit = pcall(require, "guaraci_audit")

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

local function url_decode(value)
    if type(value) ~= "string" then
        return ""
    end

    local decoded = value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)

    decoded = decoded:gsub("+", " ")
    return decoded
end

local function split_path(path)
    local parts = {}
    for token in string.gmatch(path, "[^/]+") do
        parts[#parts + 1] = token
    end
    return parts
end

local function sanitize_path(raw_path)
    if type(raw_path) ~= "string" or raw_path == "" then
        raw_path = "/"
    end

    local no_query = raw_path:match("^[^?]*") or "/"
    local decoded = url_decode(no_query)

    if decoded:find("\0", 1, true) then
        return nil, "invalid_null_byte"
    end

    decoded = decoded:gsub("\\", "/")

    local normalized = decoded
    if normalized == "" then
        normalized = "/"
    end

    if normalized:sub(1, 1) ~= "/" then
        normalized = "/" .. normalized
    end

    local parts = split_path(normalized)
    local safe_parts = {}

    for i = 1, #parts do
        local segment = parts[i]
        if segment == ".." then
            return nil, "path_traversal"
        elseif segment ~= "." and segment ~= "" then
            safe_parts[#safe_parts + 1] = segment
        end
    end

    if #safe_parts == 0 then
        return "index.gc"
    end

    local rel = table.concat(safe_parts, "/")

    if rel:sub(-1) == "/" then
        rel = rel .. "index.gc"
    elseif not rel:match("%.gc$") then
        rel = rel .. ".gc"
    end

    return rel
end

local function file_exists(path)
    local ok, result = pcall(function()
        local fh = io.open(path, "r")
        if fh then
            fh:close()
            return true
        end
        return false
    end)

    if not ok then
        return false
    end

    return result
end

function M.resolve(req_path, opts)
    opts = opts or {}

    local root = opts.templates_root or "views"
    if type(root) ~= "string" or root == "" then
        root = "views"
    end

    local relative, err = sanitize_path(req_path)
    if not relative then
        log_security("Roteador bloqueou path invalido", { path = tostring(req_path), reason = err })
        return nil, "invalid_path"
    end

    local physical_path = root .. "/" .. relative

    if not file_exists(physical_path) then
        return nil, "not_found"
    end

    return physical_path
end

function M.resolve_or_404(req, res, opts)
    local path_value = req and req.path or "/"
    local resolved, err = M.resolve(path_value, opts)

    if resolved then
        return resolved
    end

    if type(res) == "table" then
        res.status = 404
        res.body = "<h1>404 Not Found</h1>"
    end

    if err == "invalid_path" then
        log_error("Falha de roteamento por path invalido", { path = tostring(path_value) })
    end

    return nil, err
end

return M
