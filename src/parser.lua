local M = {}

local URL_ATTRS = {
    href = true,
    src = true,
    action = true,
    formaction = true,
    poster = true,
    cite = true,
    data = true,
    srcset = true
}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function last_pattern_index(str, pattern)
    local cursor = 1
    local last

    while true do
        local i = string.find(str, pattern, cursor)
        if not i then
            break
        end
        last = i
        cursor = i + 1
    end

    return last
end

local function infer_expr_context(template_source, open_start, literal_before)
    local prefix = string.sub(template_source, 1, open_start - 1):lower()
    local last_script_open = last_pattern_index(prefix, "<script[%s>]")
    local last_script_close = last_pattern_index(prefix, "</script>")
    if last_script_open and (not last_script_close or last_script_open > last_script_close) then
        return "JS_STRING"
    end

    local last_style_open = last_pattern_index(prefix, "<style[%s>]")
    local last_style_close = last_pattern_index(prefix, "</style>")
    if last_style_open and (not last_style_close or last_style_open > last_style_close) then
        return "CSS_STRING"
    end

    local lower_literal = literal_before:lower()
    local attr_name = lower_literal:match("([%w_:%-]+)%s*=%s*['\"]%s*$")
    if attr_name then
        if URL_ATTRS[attr_name] then
            return "URL_ATTR"
        end
        return "HTML_ATTR_QUOTED"
    end

    return "HTML_TEXT"
end

local function count_newlines(str)
    local _, n = str:gsub("\n", "")
    return n
end

-- Returns line and column (1-based) of byte position `pos` in `source`.
local function position_of(source, pos)
    local line, line_start = 1, 1
    local i = 1
    while true do
        local nl = string.find(source, "\n", i, true)
        if not nl or nl >= pos then
            break
        end
        line = line + 1
        line_start = nl + 1
        i = nl + 1
    end
    return line, pos - line_start + 1
end

local function compile_tokens(template)
    local lines = {}
    local cursor = 1
    local contexts = {}
    local context_info = {}
    -- line_map[compiled_line] = template line (prelude lines map to 1)
    local line_map = {}
    local compiled_line = 0

    local function emit(text, template_line)
        lines[#lines + 1] = text
        local span = count_newlines(text)
        for offset = 0, span do
            line_map[compiled_line + 1 + offset] = template_line + offset
        end
        compiled_line = compiled_line + 1 + span
    end

    emit("local __buf = {}", 1)
    emit("local function __guaraci_write(v) table.insert(__buf, tostring(v)) end", 1)
    emit("local escape = assert(escape, \"escape function is required\")", 1)
    emit(
    "local __guaraci_escape_by_context = assert(__guaraci_escape_by_context, \"__guaraci_escape_by_context function is required\")", 1)
    emit("local __guaraci_partial = assert(__guaraci_partial, \"__guaraci_partial function is required\")", 1)
    emit("local function write(_) error(\"blocked_context:RAW_TEXT_TEMPLATE\", 2) end", 1)
    emit("local function partial(name, data) return __guaraci_partial(name, data) end", 1)
    emit("local function include(name, data) __guaraci_write(__guaraci_partial(name, data)) end", 1)

    while true do
        local open_start, open_end = string.find(template, "<%", cursor, true)

        if not open_start then
            local literal = string.sub(template, cursor)
            if literal ~= "" then
                emit("__guaraci_write(" .. string.format("%q", literal) .. ")", (position_of(template, cursor)))
            end
            break
        end

        local literal = string.sub(template, cursor, open_start - 1)
        if literal ~= "" then
            emit("__guaraci_write(" .. string.format("%q", literal) .. ")", (position_of(template, cursor)))
        end

        local close_start, _ = string.find(template, "%>", open_end + 1, true)
        if not close_start then
            local line, col = position_of(template, open_start)
            return nil, "Template invalido: tag <% sem fechamento %>", { line = line, col = col, end_line = line }
        end

        local raw_block = string.sub(template, open_end + 1, close_start - 1)
        local left_trimmed = raw_block:gsub("^%s+", "")
        local block_pos = open_end + 1 + (#raw_block - #left_trimmed)
        local block_line, block_col = position_of(template, block_pos)

        if string.sub(left_trimmed, 1, 1) == "=" then
            local expr = trim(string.sub(left_trimmed, 2))
            if expr == "" then
                return nil, "Template invalido: bloco <%= %> vazio", { line = block_line, col = block_col, end_line = block_line }
            end
            local context_name = infer_expr_context(template, open_start, literal)
            contexts[#contexts + 1] = context_name
            local open_line, open_col = position_of(template, open_start)
            context_info[#context_info + 1] = {
                context = context_name,
                line = open_line,
                col = open_col,
                end_line = (position_of(template, close_start))
            }
            emit("__guaraci_write(__guaraci_escape_by_context(\"" ..
            context_name .. "\", tostring(" .. expr .. " or \"\")))", block_line)
        else
            local code = trim(raw_block)
            if code ~= "" then
                emit(code, block_line)
            end
        end

        cursor = close_start + 2
    end

    emit("return table.concat(__buf)", count_newlines(template) + 1)

    return table.concat(lines, "\n"), {
        contexts = contexts,
        context_info = context_info,
        line_map = line_map
    }
end

function M.compile(template_source)
    if type(template_source) ~= "string" then
        return nil, "Template invalido: esperado string"
    end

    return compile_tokens(template_source)
end

return M
