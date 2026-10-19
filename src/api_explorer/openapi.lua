-- Builds the simplified OpenAPI 3.0 document from the current router_v2/route_introspection
-- state. Rebuilt on every call: no cache, no file, always the live catalog (ADR-05, FR07.4).
local json_util = require("json_util")
local route_introspection = require("route_introspection")
local guaraci_version = require("guaraci_version")

local M = {}

-- descriptor field type (CLI vocabulary) -> OpenAPI type (architecture.md §3.2).
local OPENAPI_TYPE = {
    string = "string", number = "number", integer = "integer", boolean = "boolean"
}

local OPERATION_SUMMARY_VERB = { list = "List", get = "Get", create = "Create", update = "Update", delete = "Delete" }

local BODY_METHODS = { POST = true, PUT = true, PATCH = true }

-- Ordered map: preserves insertion order for JSON objects whose key set is dynamic
-- (paths, properties, responses, components.schemas) — never relies on pairs() for these
-- (architecture.md §5.5). Small fixed-key literal tables built below (a parameter object, a
-- {type=...} schema snippet) are plain Lua tables; their key order carries no meaning.
local function new_omap()
    return { __omap = true, keys = {}, values = {} }
end

local function oset(m, k, v)
    if m.values[k] == nil then
        m.keys[#m.keys + 1] = k
    end
    m.values[k] = v
    return m
end

local function is_sequential_array(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then
            return false
        end
    end
    return true
end

-- Recursive encoder: omaps use their own explicit key order; plain tables fall back to
-- pairs()/ipairs() because their key set is small and fixed by this module's own code, not by
-- runtime data. Leaf values delegate to json_util.encode (string escaping, numbers, booleans).
function M.encode(value)
    if type(value) ~= "table" then
        return json_util.encode(value)
    end

    if value.__omap then
        local parts = {}
        for _, k in ipairs(value.keys) do
            parts[#parts + 1] = json_util.encode(tostring(k)) .. ":" .. M.encode(value.values[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    if is_sequential_array(value) then
        local parts = {}
        for i = 1, #value do
            parts[#parts + 1] = M.encode(value[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local parts = {}
    for k, v in pairs(value) do
        parts[#parts + 1] = json_util.encode(tostring(k)) .. ":" .. M.encode(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function field_property(field)
    if field.type == "table" then
        return { type = "object", additionalProperties = true }
    end
    return { type = OPENAPI_TYPE[field.type] or "string" }
end

-- components.schemas.<Model>: full resource shape (id + declared fields + tenant_id when
-- the resource requires a tenant). Field order follows --fields declaration order.
local function build_resource_schema(descriptor)
    local props = new_omap()
    oset(props, "id", { type = "integer" })
    for _, field in ipairs(descriptor.fields or {}) do
        oset(props, field.name, field_property(field))
    end
    if descriptor.requires_tenant then
        oset(props, "tenant_id", { type = "string" })
    end
    return { type = "object", properties = props }
end

-- components.schemas.<Model>Input: mutation payload shape (declared fields only, `required`
-- omitted entirely when no field is required — ADR-04).
local function build_input_schema(descriptor)
    local props = new_omap()
    local required = {}
    for _, field in ipairs(descriptor.fields or {}) do
        oset(props, field.name, field_property(field))
        if field.required then
            required[#required + 1] = field.name
        end
    end
    local schema = { type = "object", properties = props }
    if #required > 0 then
        schema.required = required
    end
    return schema
end

local function summary_for(op, model)
    local lower = string.lower(model)
    local noun = (op == "list") and (lower .. "s") or lower
    return OPERATION_SUMMARY_VERB[op] .. " " .. noun
end

local function ref(model)
    return { ["$ref"] = "#/components/schemas/" .. model }
end

local function json_content(schema)
    return { ["application/json"] = { schema = schema } }
end

local function id_param()
    return { { name = "id", ["in"] = "path", required = true, schema = { type = "string" } } }
end

local function list_params()
    return {
        { name = "page", ["in"] = "query", required = false, schema = { type = "integer" } },
        { name = "per_page", ["in"] = "query", required = false, schema = { type = "integer" } }
    }
end

local function list_response_schema(model)
    local props = new_omap()
    oset(props, "data", { type = "array", items = ref(model) })
    oset(props, "page", { type = "integer" })
    oset(props, "per_page", { type = "integer" })
    oset(props, "total", { type = "integer" })
    return { type = "object", properties = props }
end

local function create_response_schema()
    local props = new_omap()
    oset(props, "ok", { type = "boolean" })
    return { type = "object", properties = props }
end

-- Operation shapes for generated (descriptor-backed) routes follow architecture.md §3.4
-- verbatim, including the exact (non-alphabetical) response ordering per operation.
local function build_generated_operation(entry, descriptor)
    local op = descriptor.operation
    local model = descriptor.model
    local operation = { operationId = entry.name, summary = summary_for(op, model) }
    local responses = new_omap()

    if op == "list" then
        operation.parameters = list_params()
        oset(responses, "200", { description = "Paginated list", content = json_content(list_response_schema(model)) })
        if descriptor.requires_tenant then
            oset(responses, "403", { description = "Tenant context required" })
        end
    elseif op == "create" then
        operation.requestBody = { required = true, content = json_content(ref(model .. "Input")) }
        oset(responses, "201", { description = "Created", content = json_content(create_response_schema()) })
        oset(responses, "400", { description = "Invalid request" })
        if descriptor.requires_tenant then
            oset(responses, "403", { description = "Tenant context required" })
        end
    elseif op == "get" then
        operation.parameters = id_param()
        oset(responses, "200", { description = "OK", content = json_content(ref(model)) })
        oset(responses, "404", { description = "Resource not found" })
        if descriptor.requires_tenant then
            oset(responses, "403", { description = "Tenant context required" })
        end
    elseif op == "update" then
        operation.parameters = id_param()
        operation.requestBody = { required = true, content = json_content(ref(model .. "Input")) }
        oset(responses, "200", { description = "OK" })
        oset(responses, "400", { description = "Invalid request" })
        if descriptor.requires_tenant then
            oset(responses, "403", { description = "Tenant context required" })
        end
        oset(responses, "404", { description = "Resource not found" })
    else -- delete
        operation.parameters = id_param()
        oset(responses, "200", { description = "OK" })
        if descriptor.requires_tenant then
            oset(responses, "403", { description = "Tenant context required" })
        end
        oset(responses, "404", { description = "Resource not found" })
    end

    operation.responses = responses
    return operation
end

-- Ad-hoc (descriptor-less) routes: path parameters extracted from the pattern, a generic
-- object body for mutating methods, and only the observable 200 — never invented fields
-- (architecture.md §3.4 notes, FR06.4).
local function build_adhoc_operation(entry)
    local operation = { operationId = entry.name }

    local params = {}
    for _, name in ipairs(entry.param_names or {}) do
        params[#params + 1] = { name = name, ["in"] = "path", required = true, schema = { type = "string" } }
    end
    if #params > 0 then
        operation.parameters = params
    end

    if BODY_METHODS[entry.method] then
        operation.requestBody = {
            required = true,
            content = json_content({ type = "object", additionalProperties = true })
        }
    end

    local responses = new_omap()
    oset(responses, "200", { description = "OK" })
    operation.responses = responses
    return operation
end

-- "/products/:id" -> "/products/{id}" (architecture.md §3.4: path parameters use {id}).
local function openapi_path(pattern)
    return (pattern:gsub(":([%w_]+)", "{%1}"))
end

local function build(opts)
    local doc = {
        openapi = "3.0.3",
        info = { title = opts.title or "Guaraci API", version = opts.version or guaraci_version }
    }

    local path_order, path_entries = {}, {}
    for _, entry in ipairs(route_introspection.all()) do
        -- The explorer's own 4 utility routes (/__guaraci/...) are framework-internal, not
        -- part of the user's API, and never get a descriptor: never document them.
        if not entry.pattern:find("^/__guaraci/") then
            if not path_entries[entry.pattern] then
                path_entries[entry.pattern] = {}
                path_order[#path_order + 1] = entry.pattern
            end
            table.insert(path_entries[entry.pattern], entry)
        end
    end

    local paths = new_omap()
    local schemas = new_omap()
    local seen_models = {}

    for _, pattern in ipairs(path_order) do
        local op_map = new_omap()
        for _, entry in ipairs(path_entries[pattern]) do
            local descriptor = entry.descriptor
            local operation
            if descriptor then
                operation = build_generated_operation(entry, descriptor)
                if not seen_models[descriptor.model] then
                    seen_models[descriptor.model] = true
                    oset(schemas, descriptor.model, build_resource_schema(descriptor))
                    oset(schemas, descriptor.model .. "Input", build_input_schema(descriptor))
                end
            else
                operation = build_adhoc_operation(entry)
            end
            oset(op_map, string.lower(entry.method), operation)
        end
        oset(paths, openapi_path(pattern), op_map)
    end

    doc.paths = paths
    doc.components = { schemas = schemas }
    return doc
end

-- Returns (doc, nil) on success or (nil, err) on failure. Callers (the future
-- GET /__guaraci/api-docs handler) are expected to map a failure to HTTP 500 and call
-- guaraci_audit.log_error("openapi_build_failed", { error = tostring(err) }).
function M.build_document(opts)
    local ok, result = pcall(build, opts or {})
    if not ok then
        return nil, result
    end
    return result
end

return M
