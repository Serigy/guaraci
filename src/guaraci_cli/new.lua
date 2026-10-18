-- guaraci new <name>: scaffolds a project from the embedded templates.
local templates = require("guaraci_cli.templates")
local util = require("guaraci_cli.util")

local M = {}

local function render(template, name)
    return (template:gsub("{{name}}", name))
end

local function directory_is_empty(dir)
    local pipe = io.popen("ls -A " .. util.shell_quote(dir) .. " 2>/dev/null")
    if not pipe then
        return false
    end
    local first = pipe:read("l")
    local ok = pipe:close()
    -- A failed listing counts as non-empty: never scaffold over something we cannot inspect.
    return first == nil and ok == true
end

-- The security headers hook is copied from the installed core so projects can customise it.
local function security_headers_source()
    local path = package.searchpath("hooks.security_headers", package.path)
    if not path then
        return nil, "hooks.security_headers not found on package.path"
    end
    return util.read_file(path)
end

function M.run(args, io_streams)
    local out, err = io_streams.stdout, io_streams.stderr
    local parsed, parse_err = util.parse_args(args, {})
    if not parsed or #parsed.positional ~= 1 then
        err:write("guaraci new: " .. (parse_err or "expected exactly one project name") ..
            "\nusage: guaraci new <name>\n")
        return 2
    end

    local target = parsed.positional[1]:gsub("/+$", "")
    local name = target:match("([^/]+)$")
    if not name or not name:match("^[%w][%w_%-%.]*$") or name:find("..", 1, true) then
        err:write("guaraci new: invalid project name '" .. target .. "' (use letters, digits, - _ .)\n")
        return 2
    end

    if util.directory_exists(target) and not directory_is_empty(target) then
        err:write("guaraci new: '" .. target .. "' already exists and is not empty\n")
        return 1
    end

    local hook_source, hook_err = security_headers_source()
    if not hook_source then
        err:write("guaraci new: " .. tostring(hook_err) .. "\n")
        return 1
    end

    local files = {
        { "app.lua", templates.app_lua },
        { "views/index.gc", render(templates.index_gc, name) },
        { "hooks/security_headers.lua", hook_source },
        { "cgi-bin/app.cgi", templates.app_cgi, executable = true },
        { "spec/index_spec.lua", render(templates.index_spec, name) },
        { "paseo.json", templates.paseo_json },
        { ".gitignore", templates.gitignore },
        { "Dockerfile.dev", templates.dockerfile },
        { "README.md", render(templates.readme, name) }
    }

    for _, dir in ipairs({ "views", "hooks", "cgi-bin", "spec" }) do
        if not os.execute("mkdir -p " .. util.shell_quote(target .. "/" .. dir)) then
            err:write("guaraci new: cannot create " .. target .. "/" .. dir .. "\n")
            return 1
        end
    end

    for _, file in ipairs(files) do
        local path = target .. "/" .. file[1]
        local ok, write_err = util.write_file(path, file[2])
        if not ok then
            err:write("guaraci new: cannot write " .. path .. ": " .. tostring(write_err) .. "\n")
            return 1
        end
        if file.executable then
            os.execute("chmod +x " .. util.shell_quote(path))
        end
        out:write("  create " .. path .. "\n")
    end

    out:write("\nDone. Next:\n  cd " .. target .. "\n  guaraci test\n  guaraci dev\n")
    return 0
end

return M
