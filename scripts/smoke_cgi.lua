package.path = "./src/?.lua;./?.lua;" .. package.path

local adapter = require("adapter_cgi")

local output = {}
local function out(chunk)
    output[#output + 1] = chunk
end

local ok = adapter.run_cgi({
    env = {
        REQUEST_METHOD = "GET",
        PATH_INFO = "/",
        QUERY_STRING = "nome=Smoke%20Test"
    },
    stdout_writer = out,
    guaraci_options = {
        templates_root = "views"
    }
})

if not ok then
    io.write("SMOKE CGI: FAILED\n")
    os.exit(1)
end

local http_response = table.concat(output)
if not http_response:find("Status: 200", 1, true) then
    io.write("SMOKE CGI: FAILED (status)\n")
    os.exit(1)
end

if not http_response:find("Smoke Test", 1, true) then
    io.write("SMOKE CGI: FAILED (body)\n")
    os.exit(1)
end

io.write("SMOKE CGI: OK\n")
