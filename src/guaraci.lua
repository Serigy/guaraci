local io_factory = require("guaraci_io")
local router = require("router")
local parser = require("parser")
local sandbox = require("sandbox")
local hooks = require("hooks")

-- Phase 10: Novos módulos para Gin-style routing
local context_store = require("context_store")
local middleware_chain = require("middleware_chain")
local router_v2 = require("router_v2")
local route_group = require("route_group")
local dataware = require("dataware")
local db = require("db")
local sqlite_driver = require("sqlite_driver")
local validator = require("validator")
local binder = require("binder")
local middleware_cors = require("middleware_cors")
local middleware_csrf = require("middleware_csrf")
local middleware_ratelimit = require("middleware_ratelimit")
local file_manager = require("file_manager")
local error_handler = require("error_handler")

local has_audit, audit = pcall(require, "guaraci_audit")

local M = {}
-- No fixed env: the default handler reads GUARACI_ENV on each call (prod when unset).
local configured_error_handler = error_handler.create_default()

local function log_error(message, context)
    if has_audit and audit and type(audit.log_error) == "function" then
        audit.log_error(message, context)
    end
end

local function safe_read_file(path)
    local ok, result_or_err = pcall(function()
        local fh = assert(io.open(path, "r"))
        local content = fh:read("*a")
        fh:close()
        return content
    end)

    if not ok then
        return nil, result_or_err
    end

    return result_or_err
end

-- Explicit routes match the raw path, so refuse traversal-shaped paths up front.
local function is_safe_route_path(path)
    if type(path) ~= "string" then
        return false
    end
    local decoded = path:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    if decoded:find("\0", 1, true) or decoded:find("\\", 1, true) then
        return false
    end
    for segment in decoded:gmatch("[^/]+") do
        if segment == ".." then
            return false
        end
    end
    return true
end

function M.escape_html(value)
    local str = tostring(value or "")
    str = str:gsub("&", "&amp;")
    str = str:gsub("<", "&lt;")
    str = str:gsub(">", "&gt;")
    str = str:gsub('"', "&quot;")
    str = str:gsub("'", "&#39;")
    return str
end

function M.handle_request(raw_req, opts)
    opts = opts or {}

    raw_req = raw_req or {}
    if raw_req.context_id == nil or raw_req.context_id == "" then
        raw_req.context_id = "ctx-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
    end

    local req = io_factory.new_request(raw_req)
    local res = io_factory.new_response(opts.base_response)
    local active_error_handler = opts.error_handler
    if not active_error_handler and type(opts.env) == "string" then
        active_error_handler = error_handler.create_default({ env = opts.env })
    end
    active_error_handler = active_error_handler or configured_error_handler

    local function apply_error(err)
        local handled = error_handler.apply(active_error_handler, err, {
            req = req,
            res = res,
            opts = opts
        })

        res.status = tonumber(handled.status) or 500
        res.headers = res.headers or {}

        local headers = handled.headers or {}
        for k, v in pairs(headers) do
            res.headers[k] = v
        end

        res.body = handled.body == nil and "" or tostring(handled.body)
        return res
    end

    local request_context = { request_id = req.context_id }
    context_store.create_context(req.context_id)

    local function cleanup_uploads()
        local ok_cleanup, cleanup_err = pcall(function()
            file_manager.cleanup_request(req.context_id)
        end)
        if not ok_cleanup then
            log_error("Falha no cleanup de upload", {
                context_id = req.context_id,
                error = tostring(cleanup_err)
            })
        end
    end

    local function finalize_response(run_after_request, template_path)
        context_store.cleanup(req.context_id)
        if run_after_request == true then
            local _, chain_err = middleware_chain.run("after_request", req, res, request_context)
            if chain_err ~= nil then
                log_error("Falha no middleware after_request", {
                    context_id = req.context_id,
                    error = tostring(chain_err)
                })
                apply_error({
                    status = 500,
                    code = "middleware_error",
                    message = "Internal Error",
                    details = "after_request"
                })
                cleanup_uploads()
                return res
            end

            local stop_after_request, stop_reason = hooks.run_stage("after_request", req, res, {
                phase = "after_request",
                template_path = template_path
            })
            if stop_reason == "hook_error" then
                apply_error({
                    status = 500,
                    code = "hook_error",
                    message = "Internal Error",
                    details = "after_request"
                })
            end
            if stop_after_request == true then
                cleanup_uploads()
                return res
            end
        end

        cleanup_uploads()
        return res
    end

    local function upload_error_status(upload_err)
        local normalized = tostring(upload_err or "")
        if normalized == "file_too_large" or normalized == "payload_too_large" then
            return 413
        end
        return 400
    end

    local ok_pipeline, pipeline_error = pcall(function()
        if opts.auto_register_default_hooks ~= false then
            local ok_defaults, defaults_err = hooks.register_default_hooks({
                security_headers_path = opts.security_headers_path
            })
            if not ok_defaults then
                log_error("Falha ao registrar hooks padrao", { error = tostring(defaults_err) })
                apply_error({
                    status = 500,
                    code = "default_hook_load_error",
                    message = "Internal Error",
                    details = defaults_err
                })
                return finalize_response(false)
            end
        end

        if req.upload_error then
            local status = upload_error_status(req.upload_error)
            apply_error({
                status = status,
                code = "upload_error",
                message = tostring(req.upload_error)
            })
            return finalize_response(false)
        end

        local stop_before_request, before_request_reason = hooks.run_stage("before_request", req, res,
            { phase = "before_request" })
        if before_request_reason == "hook_error" then
            apply_error({
                status = 500,
                code = "hook_error",
                message = "Internal Error",
                details = "before_request"
            })
            return finalize_response(false)
        end
        if stop_before_request == true then
            return finalize_response(false)
        end

        local short_circuit, chain_err, chain_ctx = middleware_chain.run("before_request", req, res, request_context)
        if type(chain_ctx) == "table" then
            request_context = chain_ctx
        end
        if short_circuit == nil then
            log_error("Falha no middleware before_request", {
                context_id = req.context_id,
                error = tostring(chain_err)
            })
            apply_error({
                status = 500,
                code = "middleware_error",
                message = "Internal Error",
                details = chain_err
            })
            return finalize_response(false)
        end
        if short_circuit == true then
            return finalize_response(false)
        end

        local route_handler, _, route_params
        if is_safe_route_path(req.path) then
            route_handler, _, route_params = router_v2.match(req.method, req.path)
        end
        if route_handler then
            request_context.params = route_params
            local handler_result = route_handler(req, res, request_context)
            if type(handler_result) == "string" then
                res.body = handler_result
            end
            return finalize_response(true)
        end

        local template_path, route_err = router.resolve_or_404(req, res, {
            templates_root = opts.templates_root
        })

        if not template_path then
            local code = route_err == "invalid_path" and "route_invalid_path" or "route_not_found"
            apply_error({
                status = 404,
                code = code,
                message = "Not Found"
            })
            return finalize_response(false)
        end

        local template_source, read_err = safe_read_file(template_path)
        if not template_source then
            log_error("Falha ao ler template", {
                path = template_path,
                error = tostring(read_err)
            })
            apply_error({
                status = 500,
                code = "template_read_error",
                message = "Internal Error",
                details = read_err
            })
            return finalize_response(false)
        end

        local stop_before_render, before_render_reason = hooks.run_stage("before_render", req, res, {
            phase = "before_render",
            template_path = template_path
        })
        if before_render_reason == "hook_error" then
            apply_error({
                status = 500,
                code = "hook_error",
                message = "Internal Error",
                details = "before_render"
            })
            return finalize_response(false)
        end
        if stop_before_render == true then
            return finalize_response(false)
        end

        local render_short, render_chain_err = middleware_chain.run("before_render", req, res, request_context)
        if render_short == nil then
            log_error("Falha no middleware before_render", {
                context_id = req.context_id,
                error = tostring(render_chain_err)
            })
            apply_error({
                status = 500,
                code = "middleware_error",
                message = "Internal Error",
                details = render_chain_err
            })
            return finalize_response(false)
        end
        if render_short == true then
            return finalize_response(false)
        end

        local compiled_lua, compile_err = parser.compile(template_source)
        if not compiled_lua then
            log_error("Falha ao compilar template", {
                path = template_path,
                error = tostring(compile_err)
            })
            apply_error({
                status = 500,
                code = "template_compile_error",
                message = "Internal Error",
                details = compile_err
            })
            return finalize_response(false)
        end

        local rendered_body, render_err = sandbox.render_template(compiled_lua, req, res, {
            escape = opts.escape or M.escape_html,
            api = opts.template_api,
            template_functions = opts.template_functions,
            template_partials = opts.template_partials,
            template_mode = opts.template_mode
        })

        if not rendered_body then
            log_error("Falha ao renderizar template", {
                path = template_path,
                error = tostring(render_err)
            })
            apply_error({
                status = 500,
                code = "template_render_error",
                message = "Internal Error",
                details = render_err
            })
            return finalize_response(false)
        end

        res.body = rendered_body

        return finalize_response(true, template_path)
    end)

    if not ok_pipeline then
        log_error("Falha inesperada no pipeline", {
            error = tostring(pipeline_error),
            context_id = req.context_id
        })
        apply_error({
            status = 500,
            code = "unhandled_exception",
            message = "Internal Error",
            details = pipeline_error
        })
        return finalize_response(false)
    end

    return pipeline_error
end

-- Phase 10: API para Gin-style routing
-- Cria novo router explícito (Fase 10)
function M.router()
    return router_v2
end

-- Cria novo grupo de rotas (Fase 10)
function M.group(prefix)
    return route_group.new(prefix, router_v2, middleware_chain)
end

-- Registra middleware global (Fase 10)
function M.use(middleware_fn, name, priority)
    return middleware_chain.use("before_request", middleware_fn, name, priority)
end

-- Cria novo contexto request-scoped (Fase 10)
function M.create_context(request_id)
    return context_store.create_context(request_id)
end

-- Limpa contextos pendentes (Fase 10)
function M.cleanup_contexts()
    return context_store.cleanup_all_pending()
end

-- Debug: retorna informações do router
function M.debug_routes()
    return router_v2.debug_routes()
end

-- Debug: retorna informações de middlewares
function M.debug_middlewares()
    local result = {}
    for _, stage in ipairs({ "before_request", "before_render", "after_request" }) do
        result[stage] = middleware_chain.get_middleware_list(stage)
    end
    return result
end

-- Phase 11: model registry (REST Dataware)
function M.model(name)
    return dataware.model(name)
end

function M.get_model(name)
    return dataware.get(name)
end

function M.list_models()
    return dataware.list()
end

function M.clear_models()
    return dataware.clear()
end

-- Inicializa Dataware com driver SQLite (backend de referencia)
-- opts:
--   db_path: caminho do arquivo sqlite (default :memory:)
--   sqlite_module: modulo lsqlite3 injetado (opcional)
--   connection: conexao sqlite ja aberta (opcional)
function M.init_dataware_sqlite(opts)
    opts = opts or {}

    local driver, err

    if opts.connection ~= nil then
        driver, err = sqlite_driver.new(opts.connection)
    else
        driver, err = sqlite_driver.from_lsqlite3(opts.db_path or ":memory:", opts.sqlite_module)
    end

    if not driver then
        log_error("Falha ao inicializar driver SQLite", {
            error = tostring(err)
        })
        return nil, err
    end

    local ok, set_err = db.set_driver(driver)
    if not ok then
        log_error("Falha ao configurar driver no wrapper db", {
            error = tostring(set_err)
        })
        return nil, set_err
    end

    return true
end

-- Phase 14: validation + binding helpers
function M.validator_schema(schema_def)
    return validator.schema(schema_def)
end

function M.validate(payload, schema_def, opts)
    return validator.validate(payload, schema_def, opts)
end

function M.bind(req, schema_def, opts)
    return binder.bind(req, schema_def, opts)
end

function M.validate_and_bind(req, schema_def, opts)
    return binder.bind(req, schema_def, opts)
end

-- Phase 14: security middleware factories
function M.middleware_cors(opts)
    return middleware_cors.create(opts)
end

function M.middleware_csrf(opts)
    return middleware_csrf.create(opts)
end

function M.middleware_ratelimit(opts)
    return middleware_ratelimit.create(opts)
end

function M.set_error_handler(handler_fn)
    if type(handler_fn) ~= "function" then
        return nil, "error_handler_must_be_function"
    end
    configured_error_handler = handler_fn
    return true
end

function M.reset_error_handler()
    configured_error_handler = error_handler.create_default()
    return true
end

return M
