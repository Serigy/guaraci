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
