local M = {}

local has_audit, audit = pcall(require, "guaraci_audit")

local ALLOWED_STAGES = {
    before_request = true,
    before_render = true,
    after_request = true
}

local registry = {
    before_request = {},
    before_render = {},
    after_request = {}
}

local defaults_loaded = false

local function log_security(message, context)
    if has_audit and audit and type(audit.log_security) == "function" then
        audit.log_security(message, context)
    end
end

local function log_error(message, context)
    if has_audit and audit and type(audit.log_error) == "function" then
        audit.log_error(message, context)
    end
end

local function ensure_stage(stage)
    if not ALLOWED_STAGES[stage] then
        return nil, "invalid_stage"
    end
    return stage
end

function M.register(stage, hook_fn, name)
    local valid_stage, err = ensure_stage(stage)
    if not valid_stage then
        return nil, err
    end

    if type(hook_fn) ~= "function" then
        return nil, "hook_must_be_function"
    end

    local entry = {
        name = type(name) == "string" and name or "anonymous_hook",
        fn = hook_fn
    }

    table.insert(registry[valid_stage], entry)
    return true
end

function M.clear(stage)
    if stage == nil then
        registry.before_request = {}
        registry.before_render = {}
        registry.after_request = {}
        defaults_loaded = false
        return true
    end

    local valid_stage, err = ensure_stage(stage)
    if not valid_stage then
        return nil, err
    end

    registry[valid_stage] = {}
    if valid_stage == "after_request" then
        defaults_loaded = false
    end
    return true
end

function M.list(stage)
    local valid_stage, err = ensure_stage(stage)
    if not valid_stage then
        return nil, err
    end

    return registry[valid_stage]
end

local function apply_short_circuit_defaults(res)
    if type(res) ~= "table" then
        return
    end

    -- Fail closed: the response default is 200, so a stop that set no status and no body means "forbidden".
    local empty_body = res.body == nil or res.body == ""
    if type(res.status) ~= "number" or (res.status == 200 and empty_body) then
        res.status = 403
    end

    if empty_body then
        if res.status == 401 then
            res.body = "<h1>401 Unauthorized</h1>"
        else
            res.body = "<h1>403 Forbidden</h1>"
        end
    end
end

function M.run_stage(stage, req, res, context)
    local valid_stage = ensure_stage(stage)
    if not valid_stage then
        return true, "invalid_stage"
    end

    local hooks = registry[valid_stage]

    for i = 1, #hooks do
        local hook = hooks[i]
        local ok, should_stop = pcall(hook.fn, req, res, context)

        if not ok then
            log_error("Hook falhou durante execucao", {
                stage = valid_stage,
                hook = hook.name,
                error = tostring(should_stop)
            })

            if type(res) == "table" then
                res.status = 500
                res.body = "Erro interno."
            end

            return true, "hook_error"
        end

        if should_stop == true then
            apply_short_circuit_defaults(res)
            log_security("Hook aplicou short-circuit", {
                stage = valid_stage,
                hook = hook.name,
                status = type(res) == "table" and res.status or nil
            })
            return true, "short_circuit"
        end
    end

    return false
end

function M.load_hook_from_file(stage, path)
    local valid_stage, err = ensure_stage(stage)
    if not valid_stage then
        return nil, err
    end

    if type(path) ~= "string" or path == "" then
        return nil, "invalid_path"
    end

    local ok, hook_or_err = pcall(dofile, path)
    if not ok then
        log_error("Falha ao carregar hook de arquivo", { stage = valid_stage, path = path, error = tostring(hook_or_err) })
        return nil, "load_error"
    end

    if type(hook_or_err) ~= "function" then
        return nil, "hook_file_must_return_function"
    end

    return M.register(valid_stage, hook_or_err, path)
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

function M.register_default_hooks(opts)
    if defaults_loaded then
        return true
    end

    opts = opts or {}
    local security_hook_path = opts.security_headers_path or "hooks/security_headers.lua"

    local ok, err
    if not opts.security_headers_path and not file_exists(security_hook_path) then
        -- Installed rock or project without hooks/: use the module shipped with the core.
        local loaded, hook_or_err = pcall(require, "hooks.security_headers")
        if loaded and type(hook_or_err) == "function" then
            ok, err = M.register("after_request", hook_or_err, "security_headers")
        else
            ok, err = nil, hook_or_err
        end
    else
        ok, err = M.load_hook_from_file("after_request", security_hook_path)
    end
    if not ok then
        log_error("Falha ao registrar hook nativo de security headers", {
            stage = "after_request",
            path = tostring(security_hook_path),
            error = tostring(err)
        })
        return nil, "default_hook_load_error"
    end

    defaults_loaded = true
    return true
end

return M
