local generate = require("guaraci_cli.generate")
local templates = require("guaraci_cli.generate_templates")
local util = require("guaraci_cli.util")

describe("guaraci_cli.generate.parse_fields", function()
    it("parses the documented grammar, preserving declaration order", function()
        local result = generate.parse_fields("title:string:required,price:number")
        assert.is_true(result.ok)
        assert.are.equal(2, #result.fields)
        assert.are.equal("title", result.fields[1].name)
        assert.are.equal("string", result.fields[1].type)
        assert.is_true(result.fields[1].required)
        assert.are.equal("price", result.fields[2].name)
        assert.are.equal("number", result.fields[2].type)
        assert.is_false(result.fields[2].required)
    end)

    it("maps every supported type, including table", function()
        local result = generate.parse_fields("a:string,b:number,c:integer,d:boolean,e:table")
        assert.is_true(result.ok)
        local types = {}
        for _, field in ipairs(result.fields) do
            types[field.name] = field.type
        end
        assert.are.equal("string", types.a)
        assert.are.equal("number", types.b)
        assert.are.equal("integer", types.c)
        assert.are.equal("boolean", types.d)
        assert.are.equal("table", types.e)
        assert.are.equal("TEXT", generate.TYPE_INFO.table.sqlite)
        assert.are.equal("object", generate.TYPE_INFO.table.openapi)
    end)

    it("returns ok=true with no fields when raw is nil or empty", function()
        local nil_result = generate.parse_fields(nil)
        assert.is_true(nil_result.ok)
        assert.are.equal(0, #nil_result.fields)
        local empty_result = generate.parse_fields("")
        assert.is_true(empty_result.ok)
        assert.are.equal(0, #empty_result.fields)
    end)

    it("rejects an empty segment", function()
        local result = generate.parse_fields("title:string,,price:number")
        assert.is_false(result.ok)
        assert.are.equal("empty_segment", result.code)
    end)

    it("rejects a duplicate field name", function()
        local result = generate.parse_fields("title:string,title:number")
        assert.is_false(result.ok)
        assert.are.equal("duplicate_field", result.code)
    end)

    it("rejects a missing type", function()
        local result = generate.parse_fields("price")
        assert.is_false(result.ok)
        assert.are.equal("missing_type", result.code)
    end)

    it("rejects an invalid field name", function()
        local result = generate.parse_fields("pr ice:string")
        assert.is_false(result.ok)
        assert.are.equal("invalid_name", result.code)
    end)

    it("rejects an unknown type", function()
        local result = generate.parse_fields("price:texto")
        assert.is_false(result.ok)
        assert.are.equal("unknown_type", result.code)
    end)

    it("rejects an unknown rule such as min:0", function()
        local result = generate.parse_fields("price:number:min:0")
        assert.is_false(result.ok)
        assert.are.equal("unknown_rule", result.code)
    end)

    it("rejects any rule other than required", function()
        local result = generate.parse_fields("price:number:email")
        assert.is_false(result.ok)
        assert.are.equal("unknown_rule", result.code)
    end)
end)

describe("guaraci_cli.generate_templates", function()
    local FIELDS = {
        { name = "title", type = "string", required = true },
        { name = "price", type = "number", required = false }
    }

    it("renders the model with ordered fields and tenant on by default", function()
        local src = templates.render_model("Product", FIELDS, {})
        assert.is_not_nil(src:find('guaraci.model%("Product"%)'))
        assert.is_not_nil(src:find('model:table%("products"%)'))
        assert.is_nil(src:find("without_tenant", 1, true))
        assert.is_not_nil(src:find('title = { type = "string", required = true }', 1, true))
        assert.is_not_nil(src:find('price = { type = "number" }', 1, true))
        assert.is_not_nil(src:find(
            "title = { type = \"string\", required = true },\n    price = { type = \"number\" }", 1, true))
    end)

    it("renders model:schema({}) when there are no fields", function()
        local src = templates.render_model("Product", {}, {})
        assert.is_not_nil(src:find("model:schema({})", 1, true))
    end)

    it("renders model:without_tenant() only for --no-tenant", function()
        local src = templates.render_model("Product", FIELDS, { no_tenant = true })
        assert.is_not_nil(src:find("model:without_tenant()", 1, true))
    end)

    it("renders a route file that calls auto_crud.generate, group.use and describes all 5 ops", function()
        local src = templates.render_routes("Product", FIELDS, {})
        assert.is_not_nil(src:find("auto_crud.generate(model, group, opts)", 1, true))
        assert.is_not_nil(src:find("group.use(validate_mutation,", 1, true))
        assert.is_not_nil(src:find("route_introspection.describe(method, pattern,", 1, true))
        assert.is_not_nil(src:find('for _, op in ipairs({ "list", "get", "create", "update", "delete" })', 1, true))
        assert.is_nil(src:find("model:find", 1, true))
        assert.is_nil(src:find("model:create", 1, true))
    end)

    it("gates the required-field check to POST/PUT only", function()
        local src = templates.render_routes("Product", FIELDS, {})
        assert.is_not_nil(src:find('method ~= "POST" and method ~= "PUT"', 1, true))
    end)

    it("fixes opts.tenant_middleware to __global__ for --no-tenant and sets requires_tenant=false", function()
        local src = templates.render_routes("Product", FIELDS, { no_tenant = true })
        assert.is_not_nil(src:find('context.tenant_id = "__global__"', 1, true))
        assert.is_not_nil(src:find("requires_tenant = false", 1, true))
    end)

    it("sets requires_tenant=true by default", function()
        local src = templates.render_routes("Product", FIELDS, {})
        assert.is_not_nil(src:find("requires_tenant = true", 1, true))
    end)

    it("renders two identical renders as byte-identical (determinism, NFR06)", function()
        local a = templates.render_routes("Product", FIELDS, {})
        local b = templates.render_routes("Product", FIELDS, {})
        assert.are.equal(a, b)
        assert.are.equal(templates.render_model("Product", FIELDS, {}), templates.render_model("Product", FIELDS, {}))
        assert.are.equal(templates.render_spec("Product", FIELDS, {}), templates.render_spec("Product", FIELDS, {}))
    end)

    it("renders the exact mount snippet", function()
        local files = { "models/product.lua", "routes/product.lua", "spec/product_spec.lua" }
        local snippet = templates.mount_snippet(files, "Product")
        assert.are.equal(
            "Criado:\n" ..
            "  models/product.lua\n" ..
            "  routes/product.lua\n" ..
            "  spec/product_spec.lua\n" ..
            "\n" ..
            "Para montar em app.lua:\n" ..
            '  local guaraci = require("guaraci")\n' ..
            '  require("routes.product")(guaraci)\n' ..
            "\n" ..
            "Em seguida:\n" ..
            "  guaraci test\n",
            snippet)
    end)

    it("renders a spec file covering list/create/invalid/404 and tenant isolation", function()
        local src = templates.render_spec("Product", FIELDS, {})
        assert.is_not_nil(src:find('it("lists resources (200)"', 1, true))
        assert.is_not_nil(src:find('it("creates a resource (201)"', 1, true))
        assert.is_not_nil(src:find('it("rejects a mutation missing a required field (400)"', 1, true))
        assert.is_not_nil(src:find('it("returns 404 for a missing resource"', 1, true))
        assert.is_not_nil(src:find('it("isolates tenants: another tenant does not see the row"', 1, true))
        assert.is_not_nil(src:find("tenant_id TEXT", 1, true))
    end)

    it("renders a --no-tenant spec without a tenant column and with the no-tenant test", function()
        local src = templates.render_spec("Product", FIELDS, { no_tenant = true })
        assert.is_nil(src:find("tenant_id TEXT", 1, true))
        assert.is_not_nil(src:find('it("does not require a tenant header"', 1, true))
    end)

    it("renders the non-table-body test when there are no fields at all", function()
        local src = templates.render_spec("Product", {}, {})
        assert.is_not_nil(src:find('it("rejects a non-table request body (400)"', 1, true))
        assert.is_not_nil(src:find('router_v2.match("POST"', 1, true))
    end)

    it("loads as valid Lua for every rendered artifact (model/routes/spec)", function()
        for _, source in ipairs({
            templates.render_model("Product", FIELDS, {}),
            templates.render_routes("Product", FIELDS, {}),
            templates.render_model("Product", {}, { no_tenant = true }),
            templates.render_routes("Product", {}, { no_tenant = true }),
            templates.render_spec("Product", FIELDS, {}),
            templates.render_spec("Product", {}, {}),
            templates.render_spec("Product", FIELDS, { no_tenant = true })
        }) do
            local chunk, err = load(source)
            assert.is_not_nil(chunk, tostring(err) .. "\n---\n" .. source)
        end
    end)
end)

describe("guaraci_cli.generate.run (usage errors, no filesystem touched)", function()
    local function run(command, args)
        local out, err = {}, {}
        local code = generate.run(args, {
            stdout = { write = function(_, s) out[#out + 1] = s end },
            stderr = { write = function(_, s) err[#err + 1] = s end },
            util = util,
            command = command
        })
        return code, table.concat(out), table.concat(err)
    end

    it("rejects an unknown generate <type>", function()
        local code, _, err = run("generate", { "model", "Product" })
        assert.are.equal(2, code)
        assert.is_not_nil(err:find("tipo desconhecido", 1, true))
    end)

    it("rejects a missing generate <type>/<name>", function()
        assert.are.equal(2, (run("generate", {})))
        assert.are.equal(2, (run("generate", { "endpoint" })))
    end)

    it("rejects a missing scaffold <name>", function()
        assert.are.equal(2, (run("scaffold", {})))
    end)

    it("rejects an invalid name (traversal, slash, whitespace)", function()
        assert.are.equal(2, (run("generate", { "endpoint", "../x" })))
        assert.are.equal(2, (run("generate", { "endpoint", "a/b" })))
        assert.are.equal(2, (run("generate", { "endpoint", "a b" })))
    end)

    it("rejects an unknown flag and a missing --fields value", function()
        local code1 = run("generate", { "endpoint", "Product", "--bogus" })
        assert.are.equal(2, code1)
        local code2 = run("generate", { "endpoint", "Product", "--fields" })
        assert.are.equal(2, code2)
    end)

    it("rejects extra positional arguments", function()
        local code = run("scaffold", { "Product", "extra" })
        assert.are.equal(2, code)
    end)

    it("rejects invalid --fields grammar with exit 2", function()
        local code, _, err = run("scaffold", { "Product", "--fields", "price:texto" })
        assert.are.equal(2, code)
        assert.is_not_nil(err:find("tipo desconhecido", 1, true))
    end)
end)

describe("guaraci_cli.generate.run (filesystem, via bin/guaraci)", function()
    local repo_root
    do
        local pipe = io.popen("pwd")
        repo_root = pipe:read("l")
        pipe:close()
    end
    local guaraci_bin = repo_root .. "/bin/guaraci"

    local function make_tmp_dir()
        local dir = os.tmpname()
        os.remove(dir)
        os.execute("mkdir -p " .. util.shell_quote(dir))
        return dir
    end

    local function run_cli(dir, args)
        local pipe = io.popen("cd " .. util.shell_quote(dir) .. " && lua5.4 " ..
            util.shell_quote(guaraci_bin) .. " " .. args .. " 2>&1")
        local output = pipe:read("a")
        local ok, _, code = pipe:close()
        return (ok and 0) or code or 1, output
    end

    it("creates exactly the three documented files and the canonical mount snippet", function()
        local dir = make_tmp_dir()
        local code, output = run_cli(dir, "generate endpoint Product --fields title:string:required,price:number")
        assert.are.equal(0, code)
        assert.is_true(util.file_exists(dir .. "/models/product.lua"))
        assert.is_true(util.file_exists(dir .. "/routes/product.lua"))
        assert.is_true(util.file_exists(dir .. "/spec/product_spec.lua"))
        assert.is_false(util.file_exists(dir .. "/app.lua"))
        assert.is_not_nil(output:find('require("routes.product")(guaraci)', 1, true))
        os.execute("rm -rf " .. util.shell_quote(dir))
    end)

    it("scaffold <name> produces byte-identical files to generate endpoint <name>", function()
        local dir_a, dir_b = make_tmp_dir(), make_tmp_dir()
        run_cli(dir_a, "generate endpoint Product --fields title:string:required,price:number")
        run_cli(dir_b, "scaffold Product --fields title:string:required,price:number")
        for _, file in ipairs({ "models/product.lua", "routes/product.lua", "spec/product_spec.lua" }) do
            assert.are.equal(util.read_file(dir_a .. "/" .. file), util.read_file(dir_b .. "/" .. file))
        end
        os.execute("rm -rf " .. util.shell_quote(dir_a) .. " " .. util.shell_quote(dir_b))
    end)

    it("refuses to overwrite an existing destination without --force, leaving all three untouched", function()
        local dir = make_tmp_dir()
        run_cli(dir, "generate endpoint Product --fields title:string:required")
        local original_model = util.read_file(dir .. "/models/product.lua")
        local original_routes = util.read_file(dir .. "/routes/product.lua")
        local original_spec = util.read_file(dir .. "/spec/product_spec.lua")
        local code, output = run_cli(dir, "generate endpoint Product --fields price:number")
        assert.are.equal(1, code)
        assert.is_not_nil(output:find("já existe", 1, true))
        assert.are.equal(original_model, util.read_file(dir .. "/models/product.lua"))
        assert.are.equal(original_routes, util.read_file(dir .. "/routes/product.lua"))
        assert.are.equal(original_spec, util.read_file(dir .. "/spec/product_spec.lua"))
        os.execute("rm -rf " .. util.shell_quote(dir))
    end)

    it("--force replaces all three only after validation passes", function()
        local dir = make_tmp_dir()
        run_cli(dir, "generate endpoint Product --fields title:string:required")
        local code = run_cli(dir, "generate endpoint Product --fields price:number --force")
        assert.are.equal(0, code)
        assert.is_not_nil(util.read_file(dir .. "/models/product.lua"):find("price", 1, true))
        assert.is_nil(util.read_file(dir .. "/models/product.lua"):find("title", 1, true))
        os.execute("rm -rf " .. util.shell_quote(dir))
    end)

    it("--force on invalid input still fails validation before writing anything", function()
        local dir = make_tmp_dir()
        local code = run_cli(dir, "generate endpoint Product --fields price:texto --force")
        assert.are.equal(2, code)
        assert.is_false(util.file_exists(dir .. "/models/product.lua"))
        os.execute("rm -rf " .. util.shell_quote(dir))
    end)

    it("creates models/, routes/ and spec/ directories when missing", function()
        local dir = make_tmp_dir()
        local code = run_cli(dir, "generate endpoint Widget")
        assert.are.equal(0, code)
        assert.is_true(util.directory_exists(dir .. "/models"))
        assert.is_true(util.directory_exists(dir .. "/routes"))
        assert.is_true(util.directory_exists(dir .. "/spec"))
        os.execute("rm -rf " .. util.shell_quote(dir))
    end)

    it("generates a working --no-tenant endpoint end to end", function()
        local dir = make_tmp_dir()
        local code, output = run_cli(dir, "generate endpoint Widget --no-tenant")
        assert.are.equal(0, code)
        assert.is_not_nil(output:find("global", 1, true))
        assert.is_not_nil(util.read_file(dir .. "/models/widget.lua"):find("without_tenant", 1, true))
        os.execute("rm -rf " .. util.shell_quote(dir))
    end)
end)
