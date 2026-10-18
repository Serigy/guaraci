-- Fails when a src/**/*.lua file is missing from guaraci-scm-1.rockspec (or points to a missing file).
-- Usage: lua5.4 scripts/check_rockspec.lua [rockspec]
local rockspec_path = arg[1] or "guaraci-scm-1.rockspec"

local spec = {}
local chunk, load_err = loadfile(rockspec_path, "t", spec)
if not chunk then
    io.stderr:write("check_rockspec: " .. tostring(load_err) .. "\n")
    os.exit(1)
end
chunk()

local listed = {}
for _, path in pairs((spec.build or {}).modules or {}) do
    listed[path] = true
end

local failures = 0
local pipe = assert(io.popen("find src -name '*.lua' | sort"))
for path in pipe:lines() do
    if not listed[path] then
        io.stderr:write("missing from rockspec: " .. path .. "\n")
        failures = failures + 1
    end
end
pipe:close()

for path in pairs(listed) do
    local fh = io.open(path, "r")
    if fh then
        fh:close()
    else
        io.stderr:write("rockspec lists a file that does not exist: " .. path .. "\n")
        failures = failures + 1
    end
end

if failures > 0 then
    io.stderr:write("ROCKSPEC CHECK: FAILED (" .. failures .. ")\n")
    os.exit(1)
end
io.write("ROCKSPEC CHECK: OK\n")
