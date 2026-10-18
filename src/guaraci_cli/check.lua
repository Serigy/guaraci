-- guaraci check: static lint for .gc templates (never executes template code).
-- JSON contract (consumed by the VS Code extension), one object per file:
--   {"file": "...", "diagnostics": [{"line", "col", "end_line", "severity", "code", "message"}]}
local parser = require("parser")
local util = require("guaraci_cli.util")

local M = {}

local BLOCKED_CONTEXTS = {
    JS_STRING = "script block",
    CSS_STRING = "style block"
}

local function json_string(value)
    local escaped = tostring(value):gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return map[c] or string.format("\\u%04x", c:byte())
    end)
    return '"' .. escaped .. '"'
end

local function encode_result(file, diagnostics)
    local items = {}
    for _, d in ipairs(diagnostics) do
        items[#items + 1] = string.format(
            '{"line":%d,"col":%d,"end_line":%d,"severity":%s,"code":%s,"message":%s}',
            d.line, d.col, d.end_line, json_string(d.severity), json_string(d.code), json_string(d.message))
    end
    return '{"file":' .. json_string(file) .. ',"diagnostics":[' .. table.concat(items, ",") .. "]}"
end

local function diagnostic(line, col, end_line, severity, code, message)
    return {
        line = line, col = col, end_line = end_line or line,
        severity = severity, code = code, message = message
    }
end

local function source_line(source, number)
    local n = 0
    for text in (source .. "\n"):gmatch("(.-)\n") do
        n = n + 1
        if n == number then
            return text
        end
    end
    return ""
end

-- Lint one template source. Returns a list of diagnostics.
function M.check_source(file, source, opts)
    opts = opts or {}
    local diagnostics = {}

    local code, meta, pos = parser.compile(source)
    if not code then
        -- On failure the second return is the message and the third the position.
        pos = pos or { line = 1, col = 1, end_line = 1 }
        diagnostics[#diagnostics + 1] = diagnostic(pos.line, pos.col, pos.end_line, "error", "template-syntax", tostring(meta))
        return diagnostics
    end

    -- Syntax only: load() compiles the chunk, it does not run it.
    local chunk, load_err = load(code, "=" .. file, "t", {})
    if not chunk then
        local compiled_line, message = tostring(load_err):match(":(%d+): (.*)$")
        local line = (compiled_line and meta.line_map[tonumber(compiled_line)]) or 1
        message = message or tostring(load_err)
        local col = 1
        local near = message:match("near '(.-)'$")
        if near and near ~= "" then
            local found = source_line(source, line):find(near, 1, true)
            if found then
                col = found
            end
        end
        diagnostics[#diagnostics + 1] = diagnostic(line, col, line, "error", "lua-syntax", message)
    end

    if opts.mode ~= "text" then
        for _, info in ipairs(meta.context_info) do
            local where = BLOCKED_CONTEXTS[info.context]
            if where then
                diagnostics[#diagnostics + 1] = diagnostic(info.line, info.col, info.end_line, "warning",
                    "blocked-context",
                    "<%= %> inside a " .. where .. " is blocked at render time (" .. info.context ..
                    "); move it out or render in text mode")
            end
        end
    end

    table.sort(diagnostics, function(a, b)
        if a.line ~= b.line then return a.line < b.line end
        return a.col < b.col
    end)
    return diagnostics
end

local USAGE = "usage: guaraci check [--json] [--mode html|text] <file.gc>...\n"

function M.run(args, io_streams)
    local out, err = io_streams.stdout, io_streams.stderr
    local parsed, parse_err = util.parse_args(args, {
        flags = { json = true },
        value_flags = { mode = true }
    })
    if not parsed then
        err:write("guaraci check: " .. parse_err .. "\n" .. USAGE)
        return 2
    end

    local mode = parsed.flags.mode or "html"
    if mode ~= "html" and mode ~= "text" then
        err:write("guaraci check: --mode must be html or text\n" .. USAGE)
        return 2
    end
    if #parsed.positional == 0 then
        err:write(USAGE)
        return 2
    end

    local findings = 0
    for _, file in ipairs(parsed.positional) do
        local source, read_err = util.read_file(file)
        local diagnostics
        if source then
            diagnostics = M.check_source(file, source, { mode = mode })
        else
            diagnostics = { diagnostic(1, 1, 1, "error", "file-unreadable", tostring(read_err)) }
        end
        findings = findings + #diagnostics

        if parsed.flags.json then
            out:write(encode_result(file, diagnostics) .. "\n")
        else
            for _, d in ipairs(diagnostics) do
                out:write(string.format("%s:%d:%d: %s: %s\n", file, d.line, d.col, d.severity, d.message))
            end
        end
    end

    return findings > 0 and 1 or 0
end

return M
