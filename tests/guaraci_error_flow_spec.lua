local hooks = require("hooks")

describe("Guaraci error flow (Phase 13)", function()
    local guaraci
    local original_router

    before_each(function()
        hooks.clear()
        original_router = package.loaded["router"]
        package.loaded["guaraci"] = nil
        guaraci = require("guaraci")
        guaraci.reset_error_handler()
    end)

    after_each(function()
        package.loaded["router"] = original_router
    end)

    it("usa content negotiation para erro de upload", function()
        local res = guaraci.handle_request({
            method = "POST",
            path = "/upload",
            headers = {
                Accept = "application/xml"
            },
            upload_error = "payload_too_large"
        }, {
            auto_register_default_hooks = false
        })

        assert.are.equal(413, res.status)
        assert.are.equal("application/xml; charset=utf-8", res.headers["Content-Type"])
        assert.is_not_nil(res.body:find("<error>", 1, true))
    end)

    it("permite configurar error handler global customizado", function()
        guaraci.set_error_handler(function(err)
            return {
                status = 418,
                headers = {
                    ["Content-Type"] = "application/json; charset=utf-8"
                },
                body = '{"error":"custom"}'
            }
        end)

        local res = guaraci.handle_request({
            method = "POST",
            path = "/upload",
            upload_error = "any"
        }, {
            auto_register_default_hooks = false
        })

        assert.are.equal(418, res.status)
        assert.is_not_nil(res.body:find("custom", 1, true))

        guaraci.reset_error_handler()
    end)

    it("padroniza erro de rota por formato", function()
        local res = guaraci.handle_request({
            method = "GET",
            path = "/rota-inexistente",
            headers = {
                Accept = "text/html"
            }
        }, {
            templates_root = "views",
            auto_register_default_hooks = false
        })

        assert.are.equal(404, res.status)
        assert.are.equal("text/html; charset=utf-8", res.headers["Content-Type"])
        assert.is_not_nil(res.body:find("Not Found", 1, true))
    end)

    it("padroniza hook_error com negotiation", function()
        hooks.register("before_render", function()
            error("hook exploded")
        end, "broken_hook")

        local res = guaraci.handle_request({
            method = "GET",
            path = "/",
            headers = {
                Accept = "application/xml"
            }
        }, {
            templates_root = "views",
            auto_register_default_hooks = false
        })

        assert.are.equal(500, res.status)
        assert.are.equal("application/xml; charset=utf-8", res.headers["Content-Type"])
        assert.is_not_nil(res.body:find("hook_error", 1, true))
    end)

    it("captura excecao nao tratada no pipeline via pcall global", function()
        package.loaded["router"] = {
            resolve_or_404 = function()
                error("panic no router")
            end
        }

        package.loaded["guaraci"] = nil
        guaraci = require("guaraci")
        guaraci.reset_error_handler()

        local res = guaraci.handle_request({
            method = "GET",
            path = "/",
            headers = {
                Accept = "application/json"
            }
        }, {
            templates_root = "views",
            auto_register_default_hooks = false
        })

        assert.are.equal(500, res.status)
        assert.are.equal("application/json; charset=utf-8", res.headers["Content-Type"])
        assert.is_not_nil(res.body:find("unhandled_exception", 1, true))
    end)
end)
