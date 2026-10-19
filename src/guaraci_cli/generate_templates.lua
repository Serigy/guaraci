-- Deterministic Lua templates for `guaraci generate endpoint` / `guaraci scaffold`
-- (architecture.md §5.1-§5.4). No timestamps, UUIDs or other non-deterministic values:
-- the same (name, fields, opts) always renders byte-identical output (NFR06).
local M = {}

local SQLITE_TYPE = {
    string = "TEXT", number = "REAL", integer = "INTEGER", boolean = "INTEGER", table = "TEXT"
}

local SAMPLE_VALUE = {
    string = '"sample"', number = "1", integer = "1", boolean = "true", table = "{}"
}

local TENANT_HEADER = '{ ["X-Tenant-Id"] = "tenant-a" }'

-- Filename/base_path normalization: lowercase, pluralized only by appending "s"
-- (architecture.md §5.1 — matches auto_crud.generate's own default, not a smarter pluralizer).
function M.resource_name(name)
    return string.lower(name) .. "s"
end

function M.model_module(name)
    return "models." .. string.lower(name)
end

function M.routes_module(name)
    return "routes." .. string.lower(name)
end

local function has_required_field(fields)
    for _, field in ipairs(fields) do
        if field.required then
            return true
        end
    end
    return false
end

-- Appends `local <var_name> = { ... }` across multiple short lines (one field per line) so
-- the line stays well under the luacheck line-length limit no matter how many --fields exist.
local function append_payload_block(lines, indent, var_name, fields)
    if #fields == 0 then
        lines[#lines + 1] = indent .. "local " .. var_name .. " = {}"
        return
    end
    lines[#lines + 1] = indent .. "local " .. var_name .. " = {"
    for _, field in ipairs(fields) do
        lines[#lines + 1] = string.format("%s    %s = %s,", indent, field.name, SAMPLE_VALUE[field.type])
    end
    lines[#lines + 1] = indent .. "}"
end

-- Joins non-empty "key = value" fragments into a single `{ ... }` request-opts literal.
local function opts_literal(fragments)
    local parts = {}
    for _, fragment in ipairs(fragments) do
        if fragment ~= "" then
            parts[#parts + 1] = fragment
        end
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function schema_field_lines(fields)
    local lines = {}
    for _, field in ipairs(fields) do
        if field.required then
            lines[#lines + 1] = string.format("    %s = { type = %q, required = true },", field.name, field.type)
        else
            lines[#lines + 1] = string.format("    %s = { type = %q },", field.name, field.type)
        end
    end
    return lines
end

-- models/<name>.lua (architecture.md §5.3).
function M.render_model(name, fields, opts)
    opts = opts or {}

    local lines = {
        'local guaraci = require("guaraci")',
        "",
        "local model = guaraci.model(" .. string.format("%q", name) .. ")",
        "model:table(" .. string.format("%q", M.resource_name(name)) .. ")"
    }

    if opts.no_tenant then
        lines[#lines + 1] = "model:without_tenant()"
    end

    if #fields == 0 then
        lines[#lines + 1] = "model:schema({})"
    else
        lines[#lines + 1] = "model:schema({"
        for _, line in ipairs(schema_field_lines(fields)) do
            lines[#lines + 1] = line
        end
        lines[#lines + 1] = "})"
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "return model"

    return table.concat(lines, "\n") .. "\n"
end

local VALIDATE_MUTATION_BODY = {
    "local function validate_mutation(req, res, context)",
    '    local method = string.upper(tostring(req.method or "GET"))',
    '    if method ~= "POST" and method ~= "PUT" then',
    "        return false",
    "    end",
    '    local payload = type(req.body_table) == "table" and req.body_table or {}',
    "    for _, field in ipairs(FIELDS) do",
    '        if field.required and (payload[field.name] == nil or payload[field.name] == "") then',
    "            res.status = 400",
    "            res.headers = res.headers or {}",
    '            res.headers["Content-Type"] = "application/json; charset=utf-8"',
    "            res.body = '{\"code\":\"invalid_request\",\"message\":\"Field ' .. field.name .. " ..
    "' is required\",\"retryable\":false}'",
    "            return true",
    "        end",
    "    end",
    "    return false",
    "end"
}

-- routes/<name>.lua (architecture.md §5.2): calls auto_crud.generate, validates required
-- fields on mutation via group.use(), and registers all five descriptors on route_introspection.
function M.render_routes(name, fields, opts)
    opts = opts or {}
    local resource = M.resource_name(name)
    local requires_tenant = not opts.no_tenant

    local lines = {
        'local auto_crud = require("auto_crud")',
        'local route_introspection = require("route_introspection")',
        "local model = require(" .. string.format("%q", M.model_module(name)) .. ")",
        "",
        "local FIELDS = {"
    }

    for _, field in ipairs(fields) do
        lines[#lines + 1] = string.format("    { name = %q, type = %q, required = %s },",
            field.name, field.type, tostring(field.required))
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""

    for _, line in ipairs(VALIDATE_MUTATION_BODY) do
        lines[#lines + 1] = line
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "return function(guaraci)"
    lines[#lines + 1] = string.format("    local group = guaraci.group(%q)", "/" .. resource)
    lines[#lines + 1] = string.format('    group.use(validate_mutation, %q, 60)', resource .. "_validate_mutation")
    lines[#lines + 1] = ""
    lines[#lines + 1] = '    local opts = { base_path = "" }'

    if opts.no_tenant then
        lines[#lines + 1] = "    opts.tenant_middleware = function(req, res, context)"
        lines[#lines + 1] = '        context.tenant_id = "__global__"'
        lines[#lines + 1] = "        return false"
        lines[#lines + 1] = "    end"
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "    auto_crud.generate(model, group, opts)"
    lines[#lines + 1] = ""
    lines[#lines + 1] = '    for _, op in ipairs({ "list", "get", "create", "update", "delete" }) do'
    lines[#lines + 1] =
        '        local method = ({ list = "GET", get = "GET", create = "POST", update = "PUT", delete = "DELETE" })[op]'
    lines[#lines + 1] = string.format(
        '        local pattern = (op == "get" or op == "update" or op == "delete") and %q or %q',
        "/" .. resource .. "/:id", "/" .. resource)
    lines[#lines + 1] = "        route_introspection.describe(method, pattern, {"
    lines[#lines + 1] = string.format(
        "            model = %q, operation = op, fields = FIELDS, requires_tenant = %s",
        name, tostring(requires_tenant))
    lines[#lines + 1] = "        })"
    lines[#lines + 1] = "    end"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    return group"
    lines[#lines + 1] = "end"

    return table.concat(lines, "\n") .. "\n"
end

-- spec/<name>_spec.lua (architecture.md §7.3): exercises the generated routes against a
-- temporary SQLite table, skipping gracefully when lsqlite3 is unavailable.
function M.render_spec(name, fields, opts)
    opts = opts or {}
    local resource = M.resource_name(name)
    local requires_tenant = not opts.no_tenant
    local header_fragment = requires_tenant and ("headers = " .. TENANT_HEADER) or ""

    local columns = { "            id INTEGER PRIMARY KEY," }
    if requires_tenant then
        columns[#columns + 1] = "            tenant_id TEXT,"
    end
    for _, field in ipairs(fields) do
        columns[#columns + 1] = string.format("            %s %s,", field.name, SQLITE_TYPE[field.type])
    end
    columns[#columns] = (columns[#columns]:gsub(",$", ""))

    local lines = {
        'package.path = "./?.lua;" .. package.path',
        "",
        'local guaraci = require("guaraci")',
        'local router_v2 = require("router_v2")',
        'local route_introspection = require("route_introspection")',
        "local mount = require(" .. string.format("%q", M.routes_module(name)) .. ")",
        "",
        "local function request(method, path, request_opts)",
        "    request_opts = request_opts or {}",
        '    local o = { auto_register_default_hooks = false, env = "dev" }',
        "    for k, v in pairs(request_opts) do o[k] = v end",
        "    return guaraci.handle_request({",
        "        method = method, path = path, headers = request_opts.headers, body_table = request_opts.body_table",
        "    }, o)",
        "end",
        "",
        string.format("describe(%q, function()", name .. " generated endpoint"),
        '    local ok_require, sqlite = pcall(require, "lsqlite3")',
        "    local temp_db_path",
        "    local connection",
        "",
        "    before_each(function()",
        "        if not ok_require then",
        "            return",
        "        end",
        "        router_v2.clear()",
        "        route_introspection.clear()",
        "        guaraci.clear_models()",
        '        temp_db_path = "spec/tmp_' .. string.lower(name) ..
        '_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)) .. ".db"',
        "        connection = sqlite.open(temp_db_path)",
        "        connection:exec([[",
        string.format("            CREATE TABLE %s (", resource)
    }

    for _, line in ipairs(columns) do
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = "            );"
    lines[#lines + 1] = "        ]])"
    lines[#lines + 1] = "        guaraci.init_dataware_sqlite({ connection = connection })"
    lines[#lines + 1] = "        mount(guaraci)"
    lines[#lines + 1] = "    end)"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    after_each(function()"
    lines[#lines + 1] = "        if connection then pcall(connection.close, connection) end"
    lines[#lines + 1] = "        if temp_db_path then pcall(os.remove, temp_db_path) end"
    lines[#lines + 1] = "    end)"
    lines[#lines + 1] = ""

    lines[#lines + 1] = '    it("lists resources (200)", function()'
    lines[#lines + 1] = "        if not ok_require then assert.is_true(true); return end"
    lines[#lines + 1] = string.format('        local res = request("GET", %q, %s)',
        "/" .. resource, opts_literal({ header_fragment }))
    lines[#lines + 1] = "        assert.are.equal(200, res.status)"
    lines[#lines + 1] = "    end)"
    lines[#lines + 1] = ""

    lines[#lines + 1] = '    it("creates a resource (201)", function()'
    lines[#lines + 1] = "        if not ok_require then assert.is_true(true); return end"
    append_payload_block(lines, "        ", "payload", fields)
    lines[#lines + 1] = string.format('        local res = request("POST", %q, %s)',
        "/" .. resource, opts_literal({ header_fragment, "body_table = payload" }))
    lines[#lines + 1] = "        assert.are.equal(201, res.status)"
    lines[#lines + 1] = "    end)"
    lines[#lines + 1] = ""

    if has_required_field(fields) then
        lines[#lines + 1] = '    it("rejects a mutation missing a required field (400)", function()'
        lines[#lines + 1] = "        if not ok_require then assert.is_true(true); return end"
        lines[#lines + 1] = string.format('        local res = request("POST", %q, %s)',
            "/" .. resource, opts_literal({ header_fragment, "body_table = {}" }))
        lines[#lines + 1] = "        assert.are.equal(400, res.status)"
        lines[#lines + 1] = "    end)"
    else
        lines[#lines + 1] = '    it("rejects a non-table request body (400)", function()'
        lines[#lines + 1] = "        if not ok_require then assert.is_true(true); return end"
        lines[#lines + 1] = string.format('        local handler = router_v2.match("POST", %q)', "/" .. resource)
        lines[#lines + 1] = "        local res = {}"
        local req_fields = { 'method = "POST"' }
        if requires_tenant then
            req_fields[#req_fields + 1] = "headers = " .. TENANT_HEADER
        end
        lines[#lines + 1] = string.format("        handler(%s, res, {})", opts_literal(req_fields))
        lines[#lines + 1] = "        assert.are.equal(400, res.status)"
        lines[#lines + 1] = "    end)"
    end
    lines[#lines + 1] = ""

    lines[#lines + 1] = '    it("returns 404 for a missing resource", function()'
    lines[#lines + 1] = "        if not ok_require then assert.is_true(true); return end"
    lines[#lines + 1] = string.format('        local res = request("GET", %q, %s)',
        "/" .. resource .. "/999999", opts_literal({ header_fragment }))
    lines[#lines + 1] = "        assert.are.equal(404, res.status)"
    lines[#lines + 1] = "    end)"
    lines[#lines + 1] = ""

    if requires_tenant then
        lines[#lines + 1] = '    it("isolates tenants: another tenant does not see the row", function()'
        lines[#lines + 1] = "        if not ok_require then assert.is_true(true); return end"
        append_payload_block(lines, "        ", "payload", fields)
        lines[#lines + 1] = string.format('        request("POST", %q, %s)',
            "/" .. resource, opts_literal({ "headers = " .. TENANT_HEADER, "body_table = payload" }))
        lines[#lines + 1] = string.format(
            '        local res = request("GET", %q, { headers = { ["X-Tenant-Id"] = "tenant-b" } })',
            "/" .. resource)
        lines[#lines + 1] = "        assert.are.equal(200, res.status)"
        lines[#lines + 1] = '        assert.is_not_nil(res.body:find(\'"total":0\', 1, true))'
        lines[#lines + 1] = "    end)"
    else
        lines[#lines + 1] = '    it("does not require a tenant header", function()'
        lines[#lines + 1] = "        if not ok_require then assert.is_true(true); return end"
        lines[#lines + 1] = string.format('        local res = request("GET", %q, {})', "/" .. resource)
        lines[#lines + 1] = "        assert.are.equal(200, res.status)"
        lines[#lines + 1] = "    end)"
    end

    lines[#lines + 1] = "end)"

    return table.concat(lines, "\n") .. "\n"
end

-- Mount snippet printed to stdout after a successful generation (architecture.md §5.4, FR03.4).
function M.mount_snippet(files, name)
    local lines = { "Criado:" }
    for _, file in ipairs(files) do
        lines[#lines + 1] = "  " .. file
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Para montar em app.lua:"
    lines[#lines + 1] = '  local guaraci = require("guaraci")'
    lines[#lines + 1] = '  require("' .. M.routes_module(name) .. '")(guaraci)'
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Em seguida:"
    lines[#lines + 1] = "  guaraci test"
    return table.concat(lines, "\n") .. "\n"
end

return M
