local error_formatter = require("error_formatter")

local M = {}

local DEFAULT_MESSAGES = {
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [403] = "Forbidden",
    [404] = "Not Found",
    [413] = "Payload Too Large",
    [500] = "Internal Error"
}

local function current_env(config)
    local from_config = config and config.env
    if type(from_config) == "string" and from_config ~= "" then
        return string.lower(from_config)
    end

    local from_os = os.getenv("GUARACI_ENV")
    if type(from_os) == "string" and from_os ~= "" then
        return string.lower(from_os)
    end

    return "prod"
end

local function normalize_error(err)
    if type(err) == "table" then
        local status = tonumber(err.status) or 500
        local code = err.code or (status >= 500 and "internal_error" or "request_error")
        local message = err.message or DEFAULT_MESSAGES[status] or "Internal Error"
        return {
            status = status,
            code = tostring(code),
            message = tostring(message),
            details = err.details
        }
    end

    if type(err) == "string" and err ~= "" then
        return {
            status = 500,
            code = "internal_error",
            message = err
        }
    end

    return {
        status = 500,
        code = "internal_error",
        message = "Internal Error"
    }
end

function M.create_default(config)
    local cfg = config or {}
    local default_format = cfg.default_format or "json"

    return function(err, context)
        local normalized = normalize_error(err)
        local req = context and context.req or {}
        local env = current_env(cfg)

        local public_message = normalized.message
        if normalized.status >= 500 and env ~= "dev" then
            public_message = "Internal Error"
        end

        local payload = {
            status = normalized.status,
            error = normalized.code,
            message = public_message,
            request_id = req.context_id
        }

        if env == "dev" and normalized.status >= 500 and normalized.details ~= nil then
            payload.details = tostring(normalized.details)
        end

        local accept = req.headers and (req.headers["Accept"] or req.headers["accept"]) or nil
        local selected = error_formatter.negotiate(accept, default_format)
        local body, content_type = error_formatter.render(payload, selected)

        return {
            status = normalized.status,
            headers = {
                ["Content-Type"] = content_type
            },
            body = body
        }
    end
end

function M.apply(handler, err, context)
    local selected_handler = handler or M.create_default()

    local ok, response_or_err = pcall(function()
        return selected_handler(err, context)
    end)

    if ok and type(response_or_err) == "table" then
        return response_or_err
    end

    local fallback = M.create_default({ env = "prod" })
    return fallback({
        status = 500,
        code = "error_handler_failure",
        message = "Internal Error",
        details = response_or_err
    }, context)
end

return M
