-- guaraci dev --container: runs the project in Docker (alpine + lua5.4 + lighttpd CGI).
-- lighttpd (not busybox httpd) because every path has to be rewritten to the single app.cgi.
local templates = require("guaraci_cli.templates")
local util = require("guaraci_cli.util")

local M = {}

M.IMAGE = "guaraci-dev"

-- Runtime config. GUARACI_ENV=dev turns on detailed error responses; LUA_PATH exposes the mounted core.
function M.lighttpd_conf()
    return [==[
server.modules = ( "mod_rewrite", "mod_setenv", "mod_cgi", "mod_accesslog" )
server.document-root = "/app"
server.port = 80
server.errorlog = "/dev/stderr"
accesslog.filename = "/dev/stdout"

setenv.add-environment = (
    "GUARACI_ENV" => "dev",
    "LUA_PATH" => "/guaraci/?.lua;;"
)

cgi.assign = ( ".cgi" => "/usr/bin/lua5.4" )

url.rewrite-once = (
    "^/(.*)$" => "/cgi-bin/app.cgi/$1"
)
]==]
end

function M.dockerfile()
    return templates.dockerfile
end

-- Directory holding adapter_cgi.lua (the core), mounted read-only into the container.
function M.core_dir()
    local path = package.searchpath("adapter_cgi", package.path)
    return path and path:match("^(.*)/[^/]+$") or nil
end

function M.run_args(opts)
    return {
        "docker", "run", "--rm", "--init",
        "-p", string.format("%d:80", opts.port),
        "-v", opts.project_dir .. ":/app",
        "-v", opts.core_dir .. ":/guaraci:ro",
        "-v", opts.conf_path .. ":/etc/lighttpd/lighttpd.conf:ro",
        M.IMAGE
    }
end

local function join(args)
    local quoted = {}
    for i, arg_value in ipairs(args) do
        quoted[i] = util.shell_quote(arg_value)
    end
    return table.concat(quoted, " ")
end

local function absolute_cwd()
    local pipe = io.popen("pwd")
    local cwd = pipe and pipe:read("l")
    if pipe then
        pipe:close()
    end
    return cwd
end

function M.run(opts, io_streams)
    local out, err = io_streams.stdout, io_streams.stderr

    if not util.file_exists("cgi-bin/app.cgi") then
        err:write("guaraci dev --container: cgi-bin/app.cgi not found (run inside a project from `guaraci new`)\n")
        return 1
    end
    if not os.execute("docker version >/dev/null 2>&1") then
        err:write("guaraci dev --container: Docker is not available (is the daemon running?)\n")
        return 1
    end

    local core_dir = M.core_dir()
    local project_dir = absolute_cwd()
    if not core_dir or not project_dir then
        err:write("guaraci dev --container: cannot locate the guaraci core or the project directory\n")
        return 1
    end
    if not core_dir:match("^/") then
        core_dir = project_dir .. "/" .. core_dir
    end

    out:write("Building image " .. M.IMAGE .. " (alpine + lua5.4 + lighttpd)...\n")
    local build = io.popen("docker build -q -t " .. M.IMAGE .. " - >/dev/null", "w")
    if not build then
        err:write("guaraci dev --container: cannot start docker build\n")
        return 1
    end
    build:write(M.dockerfile())
    if not build:close() then
        err:write("guaraci dev --container: docker build failed\n")
        return 1
    end

    local conf_path = os.tmpname()
    util.write_file(conf_path, M.lighttpd_conf())
    out:write("Guaraci dev (container) on http://localhost:" .. opts.port .. "/  (Ctrl-C to stop)\n")
    out:flush()
    local ok = os.execute(join(M.run_args({
        port = opts.port, project_dir = project_dir, core_dir = core_dir, conf_path = conf_path
    })))
    os.remove(conf_path)
    return ok and 0 or 1
end

return M
