-- Additive, read-only catalog of router_v2 routes plus the optional generator descriptor for
-- each one. Never executes handlers: it only reads router_v2's own registration metadata
-- (architecture.md §3.3). Feeds api_explorer.openapi; route/model links are explicit via
-- M.describe(), never guessed from naming conventions.
local router_v2 = require("router_v2")

local M = {}

local _descriptors = {}

-- Fixed iteration order so the same registration state always yields the same catalog order
-- (architecture.md §5.5) — never iterate methods or routes via unordered pairs().
local METHOD_ORDER = { "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD" }

local function key(method, pattern)
    return string.upper(tostring(method)) .. " " .. tostring(pattern)
end

-- Idempotent: a second call for the same (method, pattern) overwrites the descriptor.
function M.describe(method, pattern, descriptor)
    _descriptors[key(method, pattern)] = descriptor
    return true
end

function M.get(method, pattern)
    return _descriptors[key(method, pattern)]
end

-- Returns an ordered array of { method, pattern, name, param_names, descriptor } covering
-- every route currently registered in router_v2, generated or ad-hoc.
function M.all()
    local out = {}
    for _, method in ipairs(METHOD_ORDER) do
        for _, route in ipairs(router_v2.get_routes(method)) do
            out[#out + 1] = {
                method = method,
                pattern = route.pattern,
                name = route.name,
                param_names = route.param_names,
                descriptor = M.get(method, route.pattern)
            }
        end
    end
    return out
end

function M.clear()
    _descriptors = {}
end

return M
