-- guaraci dev --container: runs the project in Docker (alpine + lua5.4 + lighttpd CGI).
-- lighttpd (not busybox httpd) because every path has to be rewritten to the single app.cgi.
local templates = require("guaraci_cli.templates")
local util = require("guaraci_cli.util")

local M = {}

M.IMAGE = "guaraci-dev"

-- Runtime config. GUARACI_ENV=dev turns on detailed error responses; LUA_PATH exposes the mounted core.
function M.lighttpd_conf()
    return [==[
server.modules = ( "mod_access", "mod_alias", "mod_rewrite", "mod_setenv", "mod_cgi", "mod_accesslog" )
# Only public/ is a document root: app.lua, views/ and hooks/ are never served as files.
server.document-root = "/app/public"
alias.url = ( "/cgi-bin/" => "/app/cgi-bin/" )
server.port = 8080
server.errorlog = "/dev/stderr"
accesslog.filename = "/dev/stdout"

setenv.add-environment = (
    "GUARACI_ENV" => "dev",
    "LUA_PATH" => "/guaraci/?.lua;;",
    "GUARACI_AUDIT_LOG" => "/app/logs/guaraci_audit.log",
    "GUARACI_RATELIMIT_STORE" => "/app/logs/ratelimit.db",
    "GUARACI_UPLOAD_DIR" => "/app/uploads"
)

# Never serve dotfiles from public/ (matches `guaraci dev`).
$HTTP["url"] =~ "(^|/)[.]" {
    url.access-deny = ( "" )
}

cgi.assign = ( ".cgi" => "/usr/bin/lua5.4" )

# Existing files (public/ assets) are served directly; everything else goes to the CGI.
# Like `guaraci dev`, public/ files bypass app middleware and hooks.
url.rewrite-if-not-file = (
    "^/(?!cgi-bin/)(.*)$" => "/cgi-bin/app.cgi/$1"
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
        -- Unprivileged: run as the host user (so bind-mounted uploads/logs are writable), no capabilities.
        "--user", opts.user or "1000:1000",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
        "-p", string.format("%s:%d:8080", opts.host or "127.0.0.1", opts.port),
        "-v", opts.project_dir .. ":/app:ro",
        "-v", opts.project_dir .. "/uploads:/app/uploads",
        "-v", opts.project_dir .. "/logs:/app/logs",
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
    if project_dir:find(":", 1, true) or core_dir:find(":", 1, true) then
        err:write("guaraci dev --container: paths containing ':' cannot be mounted by docker -v (" ..
            (project_dir:find(":", 1, true) and project_dir or core_dir) .. ")\n")
        return 1
    end

    out:write("Building image " .. M.IMAGE .. " (alpine + lua5.4 + lighttpd)...\n")
    os.execute("mkdir -p uploads logs public")
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

    local uid_pipe = io.popen("id -u; id -g")
    local uid, gid = uid_pipe and uid_pipe:read("l"), uid_pipe and uid_pipe:read("l")
    if uid_pipe then
        uid_pipe:close()
    end
    opts.user = (uid and gid) and (uid .. ":" .. gid) or "1000:1000"
    if uid == "0" then
        -- Never run the server as root; bind-mounted uploads/logs must then be world-writable.
        err:write("guaraci dev --container: running as root on the host; the container will use 65534:65534 " ..
            "(chmod a+rwx uploads logs if writes fail)\n")
        opts.user = "65534:65534"
        os.execute("chmod a+rwx uploads logs 2>/dev/null")
    end

    local conf_path = os.tmpname()
    util.write_file(conf_path, M.lighttpd_conf())
    if opts.host and opts.host ~= "127.0.0.1" then
        err:write("WARNING: publishing on " .. opts.host .. " exposes dev error details to the network.\n")
    end
    out:write("Guaraci dev (container) on http://" .. (opts.host or "127.0.0.1") .. ":" .. opts.port .. "/  (Ctrl-C to stop)\n")
    out:flush()
    local ok = os.execute(join(M.run_args({
        port = opts.port, host = opts.host, user = opts.user, project_dir = project_dir, core_dir = core_dir, conf_path = conf_path
    })))
    os.remove(conf_path)
    return ok and 0 or 1
end

return M
