local container = require("guaraci_cli.container")

describe("guaraci dev --container", function()
    it("rewrites every path to the single CGI script", function()
        local conf = container.lighttpd_conf()
        assert.is_not_nil(conf:find("url.rewrite-if-not-file", 1, true))
        assert.is_not_nil(conf:find('"^/(?!cgi-bin/)(.*)$" => "/cgi-bin/app.cgi/$1"', 1, true))
        assert.is_not_nil(conf:find('server.document-root = "/app/public"', 1, true))
        assert.is_not_nil(conf:find('"GUARACI_ENV" => "dev"', 1, true))
        assert.is_not_nil(conf:find("mod_cgi", 1, true))
        assert.is_not_nil(conf:find('$HTTP["url"] =~ "(^|/)[.]"', 1, true))
        assert.is_not_nil(conf:find("GUARACI_AUDIT_LOG", 1, true))
    end)

    it("builds the docker run arguments", function()
        local args = container.run_args({ port = 8080, project_dir = "/p", core_dir = "/c", conf_path = "/t.conf" })
        local joined = table.concat(args, " ")
        assert.is_not_nil(joined:find("-p 127.0.0.1:8080:80", 1, true))
        assert.is_not_nil(joined:find("-v /p:/app:ro", 1, true))
        assert.is_not_nil(joined:find("-v /p/uploads:/app/uploads", 1, true))
        assert.is_not_nil(joined:find("-v /p/logs:/app/logs", 1, true))
        local other = table.concat(container.run_args({ port = 80, host = "0.0.0.0", project_dir = "/p",
            core_dir = "/c", conf_path = "/t" }), " ")
        assert.is_not_nil(other:find("-p 0.0.0.0:80:80", 1, true))
        assert.is_not_nil(joined:find("-v /c:/guaraci:ro", 1, true))
        assert.are.equal("guaraci-dev", args[#args])
    end)

    it("uses the alpine lua5.4 + lighttpd image", function()
        local df = container.dockerfile()
        assert.is_not_nil(df:find("FROM alpine:3.20", 1, true))
        assert.is_not_nil(df:find("lua5.4 lighttpd", 1, true))
    end)

    it("fails clearly outside a project", function()
        local errbuf = {}
        local code = container.run({ port = 8080 }, {
            stdout = { write = function() end },
            stderr = { write = function(_, s) errbuf[#errbuf + 1] = s end, }
        })
        assert.are.equal(1, code)
        assert.is_not_nil(table.concat(errbuf):find("cgi-bin/app.cgi not found", 1, true))
    end)
end)
