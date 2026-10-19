-- guaraci generate endpoint <name> / guaraci scaffold <name>: deterministic CRUD scaffolding.
-- File writing and CLI dispatch wiring land in Epic 1 Story 2; this module currently exposes
-- the parsing seam (`parse_fields`) that the templates and the future `run` build on.
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

return M
