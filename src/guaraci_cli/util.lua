local M = {}

-- Parses argv into { positional = {...}, flags = {name = value|true} }.
-- spec.value_flags lists flags that consume a value (--mode text / --mode=text).
-- Returns nil, message on unknown flags when spec.flags is given.
function M.parse_args(args, spec)
    spec = spec or {}
    local value_flags = spec.value_flags or {}
    local known = spec.flags
    local out = { positional = {}, flags = {} }
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "--" then
            for j = i + 1, #args do
                out.positional[#out.positional + 1] = args[j]
            end
            break
        end
        local name, inline = a:match("^%-%-([%w%-]+)=(.*)$")
        if not name then
            name = a:match("^%-%-([%w%-]+)$")
        end
        if name then
            if known and not known[name] and not value_flags[name] then
                return nil, "unknown option --" .. name
            end
            if value_flags[name] then
                local value = inline
                if value == nil then
                    i = i + 1
                    value = args[i]
                    if value == nil then
                        return nil, "option --" .. name .. " needs a value"
                    end
                end
                out.flags[name] = value
            else
                out.flags[name] = inline or true
            end
        else
            out.positional[#out.positional + 1] = a
        end
        i = i + 1
    end
    return out
end

function M.read_file(path)
    local fh, err = io.open(path, "rb")
    if not fh then
        return nil, err
    end
    local content = fh:read("a")
    fh:close()
    return content
end

function M.write_file(path, content)
    local fh, err = io.open(path, "wb")
    if not fh then
        return nil, err
    end
    fh:write(content)
    fh:close()
    return true
end

function M.file_exists(path)
    local fh = io.open(path, "rb")
    if fh then
        fh:close()
        return true
    end
    return false
end

-- Single-quotes a string for safe use in a POSIX shell command.
function M.shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

return M
