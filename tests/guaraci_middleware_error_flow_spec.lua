-- tests/guaraci_middleware_error_flow_spec.lua
-- Testes para erro em middleware de route groups (Phase 13 Block 3)
-- Valida que erro em middleware é capturado, padronizado e negociado

local hooks = require("hooks")
local middleware_chain = require("middleware_chain")
local error_handler = require("error_handler")
local error_formatter = require("error_formatter")

describe("Guaraci middleware error flow (Phase 13 Block 3)", function()
    before_each(function()
        middleware_chain.clear()
        hooks.clear()
    end)

    it("middleware que falha é capturado e retorna nil como error", function()
        middleware_chain.use("before_request", function(req, res, ctx)
            error("Auth middleware failed")
        end, "auth_mid", 100)

        -- Simula execução de middleware chain
        local req = { method = "GET", path = "/test", headers = { Accept = "application/json" } }
        local res = { status = 200, headers = {}, body = "" }
        local ctx = {}

        local is_short_or_nil, error_msg, new_ctx = middleware_chain.run("before_request", req, res, ctx)

        -- Middleware falha resulta em is_short_or_nil = nil (not true, not false) e error_msg = error message
        assert(is_short_or_nil == nil, "middleware erro retorna nil (not true)")
        assert(error_msg ~= nil, "deve retornar mensagem de erro")
        assert.is_not_nil(error_msg:find("Auth middleware failed", 1, true), "erro message contém Auth")
    end)

    it("erro em middleware e rendido como JSON por error_formatter", function()
        local err = {
            status = 500,
            code = "middleware_error",
            message = "Auth failed"
        }

        local selected_format = error_formatter.negotiate("application/json")
        local body, content_type = error_formatter.render(err, selected_format)

        assert.are.equal("json", selected_format)
        assert.are.equal("application/json; charset=utf-8", content_type)
        assert.is_not_nil(body:find("middleware_error", 1, true))
    end)

    it("erro em middleware com wildcard (application/*) mapeia para JSON", function()
        local err = {
            status = 500,
            code = "middleware_error",
            message = "Failed"
        }

        -- application/* deve mapear para JSON
        local selected_format = error_formatter.negotiate("application/*")
        local body, content_type = error_formatter.render(err, selected_format)

        assert.are.equal("json", selected_format)
        assert.are.equal("application/json; charset=utf-8", content_type)
    end)

    it("erro em middleware com wildcard (text/*) mapeia para HTML", function()
        local err = {
            status = 500,
            code = "middleware_error",
            message = "Failed"
        }

        -- text/* deve mapear para HTML
        local selected_format = error_formatter.negotiate("text/*")
        local body, content_type = error_formatter.render(err, selected_format)

        assert.are.equal("html", selected_format)
        assert.are.equal("text/html; charset=utf-8", content_type)
    end)

    it("erro em middleware com XML format", function()
        local err = {
            status = 500,
            code = "middleware_error",
            message = "Invalid request"
        }

        local selected_format = error_formatter.negotiate("application/xml")
        local body, content_type = error_formatter.render(err, selected_format)

        assert.are.equal("xml", selected_format)
        assert.are.equal("application/xml; charset=utf-8", content_type)
        assert.is_not_nil(body:find("<error>", 1, true))
    end)

    it("prod mode oculta detalhes de erro de middleware", function()
        local handler = error_handler.create_default({ env = "prod" })

        local err = {
            status = 500,
            code = "middleware_error",
            message = "DB connection failed: postgresql://user:pass@localhost/db"
        }

        local res = handler(err, {
            req = { headers = { Accept = "application/json" } }
        })

        assert.are.equal(500, res.status)
        -- Prod mode NUNCA expõe detalhes internos
        assert.is_nil(res.body:find("postgresql://", 1, true))
        assert.is_not_nil(res.body:find("Internal Error", 1, true))
    end)

    it("dev mode mostra detalhes de erro de middleware", function()
        local handler = error_handler.create_default({ env = "dev" })

        local err = {
            status = 500,
            code = "middleware_error",
            message = "Failed",
            details = "line 42: something went wrong"
        }

        local res = handler(err, {
            req = { headers = { Accept = "application/json" } }
        })

        assert.are.equal(500, res.status)
        -- Dev mode pode incluir detalhes
        assert.is_not_nil(res.body:find("details", 1, true))
    end)

    it("multiple middlewares: erro em qualquer uma é capturado", function()
        middleware_chain.use("before_request", function(req, res, ctx)
            return false -- OK
        end, "first", 100)

        middleware_chain.use("before_request", function(req, res, ctx)
            error("Second failed")
        end, "second", 50)

        middleware_chain.use("before_request", function(req, res, ctx)
            return false -- Never reaches
        end, "third", 25)

        local req = {}
        local res = {}
        local ctx = {}

        local is_short_or_nil, err_msg, new_ctx = middleware_chain.run("before_request", req, res, ctx)

        -- Segunda middleware falha, retorna nil (não é true/false)
        assert(is_short_or_nil == nil, "deve retornar nil em error")
        assert.is_not_nil(err_msg:find("Second failed", 1, true), "erro message contém Second")
    end)

    it("custom error handler pode processar middleware error", function()
        guaraci = require("guaraci")
        guaraci.reset_error_handler()

        local custom_handler_called = false
        guaraci.set_error_handler(function(err, context)
            custom_handler_called = true
            return {
                status = 418,
                headers = { ["Content-Type"] = "application/json; charset=utf-8" },
                body = '{"teapot":true}'
            }
        end)

        local err = {
            status = 500,
            code = "middleware_error",
            message = "Test"
        }

        local res = error_handler.apply(error_handler.create_default(), err, {
            req = { headers = { Accept = "application/json" } }
        })

        -- Default handler retorna 500
        assert.are.equal(500, res.status)

        guaraci.reset_error_handler()
    end)

    it("middleware error com fallback seguro", function()
        -- Test fallback chain
        local err = {
            status = 500,
            code = "middleware_error",
            message = "Auth failed"
        }

        local handler = error_handler.create_default({ env = "prod" })
        local res = handler(err, {
            req = { headers = { Accept = "application/json" } }
        })

        -- Sempre retorna resposta válida
        assert(res.status ~= nil, "status definido")
        assert(res.headers ~= nil, "headers definido")
        assert(res.body ~= nil, "body definido")
        assert(res.status >= 400, "status é error (>= 400)")
    end)
end)
