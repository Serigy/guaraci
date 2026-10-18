-- guaraci test: runs spec/*_spec.lua (fallback tests/) with the bundled busted-style harness.
local spec_runner = require("guaraci_cli.spec_runner")
local util = require("guaraci_cli.util")

local M = {}

local function list_specs(dir)
    local specs = {}
    local pipe = io.popen("find " .. util.shell_quote(dir) .. " -maxdepth 1 -name '*_spec.lua' 2>/dev/null | sort")
    if not pipe then
        return specs
    end
    for line in pipe:lines() do
        specs[#specs + 1] = line
    end
    pipe:close()
    return specs
end

local function directory_exists(dir)
    local ok, _, code = os.rename(dir, dir)
    return ok == true or code == 13
end

-- Returns module names (spec.index_spec) for the specs found in the first existing candidate dir.
function M.discover(dir)
    local candidates = dir and { dir } or { "spec", "tests" }
    for _, candidate in ipairs(candidates) do
        if directory_exists(candidate) then
            local modules = {}
            for _, path in ipairs(list_specs(candidate)) do
                local name = path:gsub("^%./", ""):gsub("%.lua$", ""):gsub("/", ".")
                modules[#modules + 1] = name
            end
            if #modules > 0 then
                return modules, candidate
            end
        end
    end
    return {}
end

function M.run(args, io_streams)
    local err = io_streams.stderr
    local parsed, parse_err = util.parse_args(args, {})
    if not parsed or #parsed.positional > 1 then
        err:write("guaraci test: " .. (parse_err or "too many arguments") .. "\nusage: guaraci test [spec_dir]\n")
        return 2
    end

    package.path = "./?.lua;./src/?.lua;" .. package.path
    local modules, dir = M.discover(parsed.positional[1])
    if #modules == 0 then
        err:write("guaraci test: no *_spec.lua files found in " .. (parsed.positional[1] or "spec/ or tests/") .. "\n")
        return 1
    end

    io.write("Running " .. #modules .. " spec file(s) from " .. dir .. "/\n")
    return spec_runner.run(modules) and 0 or 1
end

return M
