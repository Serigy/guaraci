-- guaraci generate endpoint <name> / guaraci scaffold <name>: deterministic CRUD scaffolding.
-- Both commands converge on generate_endpoint() so they produce byte-identical artifacts (FR01.2).
local templates = require("guaraci_cli.generate_templates")
local util = require("guaraci_cli.util")

local M = {}

-- field (CLI vocabulary) -> SQLite column type / OpenAPI type (architecture.md §3.2).
-- `validator.type_name` is identical to the CLI type name, so no separate mapping is needed.
M.TYPE_INFO = {
    string = { sqlite = "TEXT", openapi = "string" },
    number = { sqlite = "REAL", openapi = "number" },
    integer = { sqlite = "INTEGER", openapi = "integer" },
    boolean = { sqlite = "INTEGER", openapi = "boolean" },
    table = { sqlite = "TEXT", openapi = "object" }
}

local NAME_PATTERN = "^[%a_][%w_]*$"

-- Printed to stdout (by the future `run`, Epic 1 Story 2) when --fields is absent: generation
-- never refuses for lack of fields, it documents the empty-schema policy instead (ADR-04).
M.NO_FIELDS_NOTICE = "nenhum campo de negócio declarado; schema gerado com apenas a chave primária"

local function fail(code, message)
    return { ok = false, code = code, message = message }
end

-- Splits `str` on single-character separator `sep`, preserving empty leading/trailing/middle pieces.
local function split(str, sep)
    local parts = {}
    local start = 1
    while true do
        local idx = str:find(sep, start, true)
        if not idx then
            parts[#parts + 1] = str:sub(start)
            break
        end
        parts[#parts + 1] = str:sub(start, idx - 1)
        start = idx + 1
    end
    return parts
end

-- Parses the `--fields` grammar: campo:tipo[:required],campo:tipo[:required],...
-- Returns { ok = true, fields = { { name=, type=, required= }, ... } } preserving declaration
-- order, or { ok = false, code =, message = } on the first invalid segment (architecture.md §3.1).
function M.parse_fields(raw)
    if raw == nil or raw == "" then
        return { ok = true, fields = {} }
    end

    local fields = {}
    local seen = {}

    for _, segment in ipairs(split(raw, ",")) do
        if segment == "" then
            return fail("empty_segment", "segmento de campo vazio em --fields")
        end

        local parts = split(segment, ":")
        local name = parts[1]
        local type_name = parts[2]
        local rule_text = nil
        if #parts >= 3 then
            rule_text = table.concat(parts, ":", 3)
        end

        if not name or name == "" or not name:match(NAME_PATTERN) then
            return fail("invalid_name", "campo '" .. tostring(name) .. "': nome inválido")
        end

        if seen[name] then
            return fail("duplicate_field", "campo '" .. name .. "' duplicado")
        end

        if type_name == nil or type_name == "" then
            return fail("missing_type", "campo '" .. name .. "': tipo ausente")
        end

        if not M.TYPE_INFO[type_name] then
            return fail("unknown_type", "campo '" .. name .. "': tipo desconhecido '" .. type_name .. "'")
        end

        local required = false
        if rule_text ~= nil then
            if rule_text ~= "required" or #parts > 3 then
                return fail("unknown_rule", "campo '" .. name .. "': regra desconhecida '" .. rule_text ..
                    "' (somente 'required' nesta versão)")
            end
            required = true
        end

        seen[name] = true
        fields[#fields + 1] = { name = name, type = type_name, required = required }
    end

    return { ok = true, fields = fields }
end

-- <name> validation (architecture.md §5.1): letter/digit/_ first, then letters/digits/_/-.
-- Structurally excludes "/", "\\", space and ".." from the allowed character class.
local ENDPOINT_NAME_PATTERN = "^[%w_][%w_%-]*$"

-- Builds the three destination paths and re-asserts the ADR-07 traversal guard as defense in
-- depth (name validation above already excludes "/", "\\" and ".." structurally).
local function target_paths(name)
    local lower = string.lower(name)
    local paths = {
        model = "models/" .. lower .. ".lua",
        routes = "routes/" .. lower .. ".lua",
        spec = "spec/" .. lower .. "_spec.lua"
    }
    for _, path in pairs(paths) do
        if path:find("..", 1, true) or not path:match("^[%w_%-/]+%.lua$") then
            return nil, path
        end
    end
    return paths
end

local function generate_endpoint(name, raw_flags, io_streams)
    local out, err, command = io_streams.stdout, io_streams.stderr, io_streams.command

    if not name or not name:match(ENDPOINT_NAME_PATTERN) then
        err:write("guaraci " .. command .. ": invalid name '" .. tostring(name) ..
            "' (use letters, digits, _ -)\n")
        return 2
    end

    local parsed, parse_err = util.parse_args(raw_flags, {
        value_flags = { fields = true },
        flags = { ["no-tenant"] = true, force = true }
    })
    if not parsed then
        err:write("guaraci " .. command .. ": " .. parse_err .. "\n")
        return 2
    end
    if #parsed.positional > 0 then
        err:write("guaraci " .. command .. ": unexpected argument '" .. parsed.positional[1] .. "'\n")
        return 2
    end

    local field_result = M.parse_fields(parsed.flags.fields)
    if not field_result.ok then
        err:write("guaraci " .. command .. ": " .. field_result.message .. "\n")
        return 2
    end

    local paths, bad_path = target_paths(name)
    if not paths then
        err:write("guaraci " .. command .. ": refusing unsafe path '" .. tostring(bad_path) .. "'\n")
        return 2
    end

    local force = parsed.flags.force == true
    local conflicts = {}
    for _, key in ipairs({ "model", "routes", "spec" }) do
        if util.file_exists(paths[key]) and not force then
            conflicts[#conflicts + 1] = paths[key]
        end
    end
    if #conflicts > 0 then
        err:write("guaraci " .. command .. ": destino já existe (use --force para substituir):\n")
        for _, path in ipairs(conflicts) do
            err:write("  " .. path .. "\n")
        end
        return 1
    end

    for _, dir in ipairs({ "models", "routes", "spec" }) do
        if not os.execute("mkdir -p " .. util.shell_quote(dir)) then
            err:write("guaraci " .. command .. ": cannot create directory '" .. dir .. "'\n")
            return 1
        end
    end

    local opts = { no_tenant = parsed.flags["no-tenant"] == true }
    local files = {
        { paths.model, templates.render_model(name, field_result.fields, opts) },
        { paths.routes, templates.render_routes(name, field_result.fields, opts) },
        { paths.spec, templates.render_spec(name, field_result.fields, opts) }
    }

    for _, file in ipairs(files) do
        local ok, write_err = util.write_file(file[1], file[2])
        if not ok then
            err:write("guaraci " .. command .. ": cannot write " .. file[1] .. ": " .. tostring(write_err) .. "\n")
            return 1
        end
    end

    local notes = {}
    if opts.no_tenant then
        notes[#notes + 1] = "Tenant: modo global (--no-tenant, require_tenant = false)."
    else
        notes[#notes + 1] = "Tenant: multi-tenant (padrão, require_tenant = true)."
    end
    if #field_result.fields == 0 then
        notes[#notes + 1] = "Aviso: " .. M.NO_FIELDS_NOTICE .. "."
    end

    out:write(table.concat(notes, "\n") .. "\n\n")
    out:write(templates.mount_snippet({ paths.model, paths.routes, paths.spec }, name))

    return 0
end

local USAGE = "uso: guaraci generate endpoint <name> [--fields campo:tipo[:required],...] [--no-tenant] [--force]\n" ..
    "     guaraci scaffold <name> [--fields ...] [--no-tenant] [--force]\n"

-- guaraci generate <type> <name> [...] / guaraci scaffold <name> [...] (architecture.md §4.5).
function M.run(args, io_streams)
    local err = io_streams.stderr
    local command = io_streams.command or "generate"

    if command == "scaffold" then
        local name = args[1]
        if not name then
            err:write("guaraci scaffold: nome obrigatório\n" .. USAGE)
            return 2
        end
        local rest = {}
        for i = 2, #args do
            rest[#rest + 1] = args[i]
        end
        return generate_endpoint(name, rest, io_streams)
    end

    local type_name = args[1]
    if type_name ~= "endpoint" then
        err:write("generate <type>: tipo desconhecido '" .. tostring(type_name) .. "' (suportado: endpoint)\n" ..
            USAGE)
        return 2
    end

    local name = args[2]
    if not name then
        err:write("guaraci generate endpoint: nome obrigatório\n" .. USAGE)
        return 2
    end

    local rest = {}
    for i = 3, #args do
        rest[#rest + 1] = args[i]
    end
    return generate_endpoint(name, rest, io_streams)
end

return M
