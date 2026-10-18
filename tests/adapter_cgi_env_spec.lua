local adapter = require("adapter_cgi")

local function fake_getenv(vars)
    return function(name) return vars[name] end
end

describe("adapter_cgi.env_from_os", function()
    it("reads standard CGI vars and allow-listed headers only", function()
        local env = adapter.env_from_os({
            getenv = fake_getenv({
                REQUEST_METHOD = "POST",
                PATH_INFO = "/x",
                QUERY_STRING = "a=1",
                HTTP_COOKIE = "sid=1",
                HTTP_X_CSRF_TOKEN = "tok",
                HTTP_X_SECRET_INTERNAL = "no"
            })
        })
        assert(env.REQUEST_METHOD == "POST")
        assert(env.PATH_INFO == "/x")
        assert(env.HTTP_COOKIE == "sid=1")
        assert(env.HTTP_X_CSRF_TOKEN == "tok")
        assert(env.HTTP_X_SECRET_INTERNAL == nil)
    end)

    it("honours extra_headers", function()
        local env = adapter.env_from_os({
            getenv = fake_getenv({ HTTP_X_CUSTOM = "v" }),
            extra_headers = { "X-Custom" }
        })
        assert(env.HTTP_X_CUSTOM == "v")
    end)

    it("run_cgi builds its env from env_from_os when opts.env is nil", function()
        local out = {}
        adapter.run_cgi({
            getenv = fake_getenv({ REQUEST_METHOD = "GET", PATH_INFO = "/", QUERY_STRING = "nome=Env" }),
            stdout_writer = function(c) out[#out + 1] = c end,
            guaraci_options = { templates_root = "views" }
        })
        local text = table.concat(out)
        assert(text:find("Status: 200", 1, true), text)
        assert(text:find("Env", 1, true))
    end)
end)

describe("adapter_cgi request hardening", function()
    local function req_with(env)
        env.REQUEST_METHOD = env.REQUEST_METHOD or "GET"
        env.PATH_INFO = env.PATH_INFO or "/"
        return adapter.request_from_cgi(env, function() return "" end)
    end

    it("accepts well-formed X-Request-Id and rejects hostile ones", function()
        assert.are.equal("req-abc_123", req_with({ HTTP_X_REQUEST_ID = "req-abc_123" }).context_id)
        for _, bad in ipairs({ "short", "../../etc/passwd", string.rep("a", 65), 'a"b<script>12345', "abc def 1234" }) do
            local id = req_with({ HTTP_X_REQUEST_ID = bad }).context_id
            assert.is_true(id ~= bad, bad)
            assert.is_not_nil(id:match("^[%w%-_]+$"))
        end
    end)

    it("keeps Apache mod_unique_id values (they contain @ and -)", function()
        local id = "Zx9@-abcDEF123456789012"
        assert.are.equal(id, req_with({ UNIQUE_ID = id }).context_id)
    end)

    it("prefers server-provided ids over the client's X-Request-Id", function()
        local req = req_with({ UNIQUE_ID = "server-id-123456", HTTP_X_REQUEST_ID = "client-id-123456" })
        assert.are.equal("server-id-123456", req.context_id)
        assert.are.equal("client-id-123456", req.client_request_id)
    end)

    it("takes remote_addr from REMOTE_ADDR, not from headers", function()
        local req = req_with({ REMOTE_ADDR = "203.0.113.9", HTTP_X_FORWARDED_FOR = "1.2.3.4" })
        assert.are.equal("203.0.113.9", req.remote_addr)
    end)

    it("HTTP_CONTENT_LENGTH cannot shadow CONTENT_LENGTH", function()
        local read = nil
        local req = adapter.request_from_cgi({
            REQUEST_METHOD = "POST", PATH_INFO = "/", CONTENT_LENGTH = "3", HTTP_CONTENT_LENGTH = "999"
        }, function(len) read = len; return "abc" end)
        assert.are.equal(3, read)
        assert.are.equal("abc", req.body)
        assert.are.equal("3", req.headers["Content-Length"])
    end)

    it("env_from_os passes X-Forwarded-For through as plain header data", function()
        local env = adapter.env_from_os({ getenv = function(n) return ({ HTTP_X_FORWARDED_FOR = "9.9.9.9" })[n] end })
        assert.are.equal("9.9.9.9", env.HTTP_X_FORWARDED_FOR)
    end)
end)

describe("adapter_cgi response splitting", function()
    local function render(res)
        local out = {}
        adapter.response_to_cgi(res, function(c) out[#out + 1] = c end)
        return table.concat(out)
    end

    it("rejects CRLF in header values", function()
        local text = render({ status = 302, headers = { Location = "/x\r\nSet-Cookie: pwn=1" }, body = "b" })
        assert.is_not_nil(text:find("^Status: 500"))
        assert.is_nil(text:find("pwn", 1, true))
    end)

    it("rejects NUL, LF and bad header names", function()
        assert.is_not_nil(render({ headers = { A = "x\ny" } }):find("^Status: 500"))
        assert.is_not_nil(render({ headers = { A = "x\0y" } }):find("^Status: 500"))
        assert.is_not_nil(render({ headers = { ["Bad Name"] = "x" } }):find("^Status: 500"))
        assert.is_not_nil(render({ headers = { ["X-Ok"] = "fine" } }):find("^Status: 200"))
    end)
end)
