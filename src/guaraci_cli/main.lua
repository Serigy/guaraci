local util = require("guaraci_cli.util")

local M = {}

-- Exit codes: 0 ok, 1 findings or failures, 2 usage error.
M.EXIT_OK, M.EXIT_FAIL, M.EXIT_USAGE = 0, 1, 2

local COMMANDS = {
    { name = "new", module = "guaraci_cli.new", summary = "create a new project: guaraci new <name>" },
    { name = "check", module = "guaraci_cli.check", summary = "lint .gc templates: guaraci check [--json] [--mode text] <files>" },
    { name = "test", module = "guaraci_cli.test", summary = "run spec/*_spec.lua (fallback tests/)" },
    {
        name = "dev", module = "guaraci_cli.dev",
        summary = "dev server: guaraci dev [--port 8080] [--host H] [--container]\n" ..
            "             (public/ bypasses app middleware)"
    },
    {
        name = "generate", module = "guaraci_cli.generate",
        summary = "generate <type> <name> [--fields ..] [--no-tenant] [--force]: scaffold endpoint"
    },
    {
        name = "scaffold", module = "guaraci_cli.generate",
        summary = "alias: guaraci scaffold <name> == guaraci generate endpoint <name>"
    },
    { name = "version", summary = "print the version" },
    { name = "help", summary = "show this help" }
}

local function usage_text()
    local lines = { "Usage: guaraci <command> [options]", "", "Commands:" }
    for _, cmd in ipairs(COMMANDS) do
        lines[#lines + 1] = string.format("  %-8s %s", cmd.name, cmd.summary)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Exit codes: 0 ok, 1 findings or failures, 2 usage error."
    return table.concat(lines, "\n") .. "\n"
end

function M.run(argv, streams)
    argv = argv or {}
    local out = (streams and streams.stdout) or io.stdout
    local err = (streams and streams.stderr) or io.stderr

    local name = argv[1]
    if name == nil then
        err:write(usage_text())
        return M.EXIT_USAGE
    end

    if name == "help" or name == "--help" or name == "-h" then
        out:write(usage_text())
        return M.EXIT_OK
    end

    if name == "version" or name == "--version" or name == "-v" then
        out:write(require("guaraci_version") .. "\n")
        return M.EXIT_OK
    end

    local command
    for _, cmd in ipairs(COMMANDS) do
        if cmd.name == name and cmd.module then
            command = cmd
        end
    end
    if not command then
        err:write("guaraci: unknown command '" .. tostring(name) .. "'\n\n" .. usage_text())
        return M.EXIT_USAGE
    end

    local ok, mod = pcall(require, command.module)
    if not ok then
        err:write("guaraci: command '" .. name .. "' is unavailable: " .. (tostring(mod):match("^[^\n]*")) .. "\n")
        return M.EXIT_FAIL
    end

    local rest = {}
    for i = 2, #argv do
        rest[#rest + 1] = argv[i]
    end
    local code = mod.run(rest, { stdout = out, stderr = err, util = util, command = name })
    return code or M.EXIT_OK
end

return M
