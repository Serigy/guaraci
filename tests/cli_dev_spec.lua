local dev = require("guaraci_cli.dev")
local util = require("guaraci_cli.util")

local function fake_client(raw)
    local pos = 1
    return {
        receive = function(_, what)
            if what == "*l" then
                local eol = raw:find("\r\n", pos, true)
                if not eol then return nil, "closed" end
                local line = raw:sub(pos, eol - 1)
                pos = eol + 2
                return line
            end
            local chunk = raw:sub(pos, pos + what - 1)
            pos = pos + what
            if #chunk < what then return nil, "closed" end
            return chunk
        end
    }
end

describe("guaraci dev", function()
    it("parses requests and builds the CGI env", function()
        local req = dev.read_request(fake_client(
            "POST /a%20b?x=1 HTTP/1.1\r\nHost: h\r\nContent-Type: text/plain\r\nContent-Length: 3\r\nX-CSRF-Token: t\r\n\r\nabc"))
        assert.are.equal("POST", req.method)
        assert.are.equal("abc", req.body)
        local env = dev.cgi_env(req, "127.0.0.1", 8080)
        assert.are.equal("/a b", env.PATH_INFO)
        assert.are.equal("x=1", env.QUERY_STRING)
        assert.are.equal("text/plain", env.CONTENT_TYPE)
        assert.are.equal("t", env.HTTP_X_CSRF_TOKEN)
        assert.are.equal("3", env.CONTENT_LENGTH)
    end)

    it("rejects malformed and oversized requests", function()
        local req, status = dev.read_request(fake_client("garbage\r\n\r\n"))
        assert.is_nil(req)
        assert.are.equal(400, status)
        local _, big = dev.read_request(fake_client("POST / HTTP/1.1\r\nContent-Length: 99999999999\r\n\r\n"))
        assert.are.equal(413, big)
    end)

    it("maps CGI output to an HTTP status line", function()
        local http = dev.cgi_to_http("Status: 404 Not Found\r\nX-A: 1\r\n\r\nbody", "GET")
        assert.is_not_nil(http:find("^HTTP/1.1 404 Not Found\r\nX%-A: 1\r\nConnection: close\r\n\r\nbody"))
        assert.is_nil(dev.cgi_to_http("Status: 200 OK\r\n\r\nbody", "HEAD"):find("body", 1, true))
    end)

    it("serves public files but never dotfiles or traversal", function()
        local dir = os.tmpname()
        os.remove(dir)
        os.execute("mkdir -p '" .. dir .. "/public'")
        util.write_file(dir .. "/public/a.css", "x{}")
        util.write_file(dir .. "/public/.secret", "s")
        util.write_file(dir .. "/outside.txt", "o")
        local function get(path) return dev.static_response({ method = "GET", path = path }, dir .. "/public") end
        assert.is_not_nil(get("/a.css"):find("text/css", 1, true))
        assert.is_nil(get("/.secret"))
        assert.is_nil(get("/../outside.txt"))
        assert.is_nil(get("/%2e%2e/outside.txt"))
        assert.is_nil(get("/a.css%00.png"))
        os.execute("rm -rf '" .. dir .. "'")
    end)

    it("reloads app.lua on every request", function()
        local app = os.tmpname()
        util.write_file(app, 'require("guaraci").router().get("/x", function(req, res) res.body = "one" end)')
        local config = { app_path = app, host = "h", port = 1, baseline = (function()
            local b = {}
            for k in pairs(package.loaded) do b[k] = true end
            return b
        end)() }
        local req = { method = "GET", target = "/x", path = "/x", query = "", headers = {}, body = "" }
        assert.is_not_nil(dev.dispatch(req, config):find("one", 1, true))
        util.write_file(app, 'require("guaraci").router().get("/x", function(req, res) res.body = "two" end)')
        assert.is_not_nil(dev.dispatch(req, config):find("two", 1, true))
        util.write_file(app, "this is not lua")
        assert.is_not_nil(dev.dispatch(req, config):find("HTTP/1.1 500", 1, true))
        os.remove(app)
        require("router_v2").clear()
    end)

    it("explains how to get luasocket when it is missing", function()
        local app = os.tmpname()
        util.write_file(app, "return {}")
        local saved = { loaded = package.loaded.socket, path = package.path, cpath = package.cpath }
        package.loaded.socket = nil
        package.path, package.cpath = "", ""
        local searchers = package.searchers
        package.searchers = {}
        local errbuf = {}
        local code = dev.run({ "--app", app }, {
            stdout = { write = function() end },
            stderr = { write = function(_, s) errbuf[#errbuf + 1] = s end }
        })
        package.searchers = searchers
        package.loaded.socket, package.path, package.cpath = saved.loaded, saved.path, saved.cpath
        os.remove(app)
        assert.are.equal(1, code)
        local text = table.concat(errbuf)
        assert.is_not_nil(text:find("luarocks install luasocket", 1, true))
        assert.is_not_nil(text:find("--container", 1, true))
    end)

    it("validates usage", function()
        local sink = { write = function() end }
        assert.are.equal(2, dev.run({ "--port", "abc" }, { stdout = sink, stderr = sink }))
        assert.are.equal(2, dev.run({ "--wat" }, { stdout = sink, stderr = sink }))
    end)
end)
