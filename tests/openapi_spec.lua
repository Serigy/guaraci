local router_v2 = require("router_v2")
local route_introspection = require("route_introspection")
local openapi = require("api_explorer.openapi")
local audit = require("guaraci_audit")
local guaraci_random = require("guaraci_random")

local function noop(req, res) return res end

local PRODUCT_FIELDS = {
    { name = "title", type = "string", required = true },
    { name = "price", type = "number", required = false }
}

local function register_product_crud(requires_tenant)
    router_v2.get("/products", noop, "products_list")
    router_v2.post("/products", noop, "products_create")
    router_v2.get("/products/:id", noop, "products_get")
    router_v2.put("/products/:id", noop, "products_update")
    router_v2.delete("/products/:id", noop, "products_delete")

    for _, op in ipairs({ "list", "get", "create", "update", "delete" }) do
        local method = ({ list = "GET", get = "GET", create = "POST", update = "PUT", delete = "DELETE" })[op]
        local pattern = (op == "get" or op == "update" or op == "delete") and "/products/:id" or "/products"
        route_introspection.describe(method, pattern, {
            model = "Product", operation = op, fields = PRODUCT_FIELDS, requires_tenant = requires_tenant
        })
    end
end

describe("api_explorer.openapi", function()
    before_each(function()
        router_v2.clear()
        route_introspection.clear()
    end)

    after_each(function()
        router_v2.clear()
        route_introspection.clear()
    end)

    it("builds the documented envelope with default title/version", function()
        local doc = openapi.build_document({})
        assert.are.equal("3.0.3", doc.openapi)
        assert.are.equal("Guaraci API", doc.info.title)
        assert.is_not_nil(doc.info.version)
    end)

    it("honors a custom title/version", function()
        local doc = openapi.build_document({ title = "My API", version = "9.9.9" })
        assert.are.equal("My API", doc.info.title)
        assert.are.equal("9.9.9", doc.info.version)
    end)

    it("matches the architecture.md §3.4 shape for a generated Product resource", function()
        register_product_crud(true)
        local doc = openapi.build_document({})
        local encoded = openapi.encode(doc)

        -- `paths` and each path's method map are omaps: key order is guaranteed.
        assert.is_not_nil(encoded:find('"/products":{"get":', 1, true))
        local products_at = encoded:find('"/products":{', 1, true)
        local products_id_at = encoded:find('"/products/{id}":{', 1, true)
        assert.is_true(products_at < products_id_at)

        -- Everything below is content-presence only: the *operation* object itself (and a
        -- parameter/response-value object) is a plain table, so its own key order is not
        -- guaranteed — only paths/per-path-methods/responses-keys/properties/schemas are.
        assert.is_not_nil(encoded:find('"operationId":"products_list"', 1, true))
        assert.is_not_nil(encoded:find('"summary":"List products"', 1, true))
        assert.is_not_nil(encoded:find('"name":"page"', 1, true))
        assert.is_not_nil(encoded:find('"name":"per_page"', 1, true))
        assert.is_not_nil(encoded:find('"description":"Paginated list"', 1, true))
        assert.is_not_nil(encoded:find('"$ref":"#/components/schemas/Product"', 1, true))
        -- `responses` is an omap: "200" must precede "403" for the list operation.
        assert.is_true((encoded:find('"200":', 1, true)) < (encoded:find('"403":', 1, true)))
        assert.is_not_nil(encoded:find('"403":{"description":"Tenant context required"}', 1, true))

        assert.is_not_nil(encoded:find('"operationId":"products_create"', 1, true))
        assert.is_not_nil(encoded:find('"$ref":"#/components/schemas/ProductInput"', 1, true))
        assert.is_not_nil(encoded:find('"description":"Created"', 1, true))
        assert.is_not_nil(encoded:find('"400":{"description":"Invalid request"}', 1, true))

        assert.is_not_nil(encoded:find('"operationId":"products_get"', 1, true))
        assert.is_not_nil(encoded:find('"name":"id"', 1, true))
        assert.is_not_nil(encoded:find('"in":"path"', 1, true))
        assert.is_not_nil(encoded:find('"404":{"description":"Resource not found"}', 1, true))

        -- `components.schemas` is an omap (Product before ProductInput); each schema's
        -- `properties` is itself an omap (field declaration order).
        local product_at = encoded:find('"Product":{', 1, true)
        local product_input_at = encoded:find('"ProductInput":{', 1, true)
        assert.is_true(product_at < product_input_at)
        assert.is_not_nil(encoded:find(
            '"properties":{"id":{"type":"integer"},"title":{"type":"string"},' ..
            '"price":{"type":"number"},"tenant_id":{"type":"string"}}', 1, true))
        assert.is_not_nil(encoded:find(
            '"properties":{"title":{"type":"string"},"price":{"type":"number"}}', 1, true))
        assert.is_not_nil(encoded:find('"required":["title"]', 1, true))
    end)

    it("omits tenant_id/403 and required when --no-tenant / no fields", function()
        router_v2.get("/widgets", noop, "widgets_list")
        route_introspection.describe("GET", "/widgets", {
            model = "Widget", operation = "list", fields = {}, requires_tenant = false
        })
        local encoded = openapi.encode(openapi.build_document({}))
        assert.is_nil(encoded:find("tenant_id", 1, true))
        assert.is_nil(encoded:find("Tenant context required", 1, true))
        -- The {type=, properties=} wrapper is a plain 2-key table: either key order is valid.
        assert.is_not_nil(
            encoded:find('"Widget":{"type":"object","properties":{"id":{"type":"integer"}}}', 1, true) or
            encoded:find('"Widget":{"properties":{"id":{"type":"integer"}},"type":"object"}', 1, true))
    end)

    it("maps the table field type to object/additionalProperties=true", function()
        router_v2.post("/notes", noop, "notes_create")
        route_introspection.describe("POST", "/notes", {
            model = "Note",
            operation = "create",
            fields = { { name = "attrs", type = "table", required = false } },
            requires_tenant = true
        })
        local encoded = openapi.encode(openapi.build_document({}))
        -- The {type=, additionalProperties=} wrapper is a plain 2-key table: either order is valid.
        assert.is_not_nil(
            encoded:find('"attrs":{"type":"object","additionalProperties":true}', 1, true) or
            encoded:find('"attrs":{"additionalProperties":true,"type":"object"}', 1, true))
    end)

    it("gives an ad-hoc parametrized route only path parameters and a generic body schema", function()
        router_v2.put("/legacy/:slug", noop, "legacy_put")
        local doc = openapi.build_document({})
        local encoded = openapi.encode(doc)

        assert.is_not_nil(encoded:find('"/legacy/{slug}"', 1, true))
        assert.is_not_nil(encoded:find('"name":"slug"', 1, true))
        assert.is_not_nil(encoded:find('"in":"path"', 1, true))
        assert.is_not_nil(
            encoded:find('"type":"object","additionalProperties":true', 1, true) or
            encoded:find('"additionalProperties":true,"type":"object"', 1, true))
        assert.is_not_nil(encoded:find('"responses":{"200":{"description":"OK"}}', 1, true))
        -- No invented properties anywhere: this fixture has no descriptor-backed routes at all.
        assert.is_nil(encoded:find('"properties"', 1, true))
    end)

    it("does not emit a parameters key for an operation with none (create)", function()
        router_v2.post("/products", noop, "products_create")
        route_introspection.describe("POST", "/products", {
            model = "Product", operation = "create", fields = {}, requires_tenant = false
        })
        local encoded = openapi.encode(openapi.build_document({}))
        assert.is_not_nil(encoded:find('"operationId":"products_create"', 1, true))
        assert.is_nil(encoded:find('"parameters"', 1, true))
    end)

    it("produces byte-identical encodings for two equivalent builds", function()
        register_product_crud(true)
        local a = openapi.encode(openapi.build_document({}))
        local b = openapi.encode(openapi.build_document({}))
        assert.are.equal(a, b)
    end)

    it("never documents the explorer's own /__guaraci/ utility routes", function()
        router_v2.get("/__guaraci/api-docs", noop, "api_docs")
        router_v2.get("/__guaraci/explorer", noop, "explorer_page")
        router_v2.get("/__guaraci/explorer/app.js", noop, "explorer_js")
        router_v2.get("/__guaraci/explorer/style.css", noop, "explorer_css")
        register_product_crud(true)

        local encoded = openapi.encode(openapi.build_document({}))
        assert.is_nil(encoded:find("__guaraci", 1, true))
        assert.is_not_nil(encoded:find('"/products"', 1, true))
    end)

    it("reflects a route registered between two builds without a process restart", function()
        router_v2.get("/products", noop, "products_list")
        route_introspection.describe("GET", "/products", { model = "Product", operation = "list", fields = {} })
        local before = openapi.encode(openapi.build_document({}))
        assert.is_nil(before:find("/widgets", 1, true))

        router_v2.get("/widgets", noop, "widgets_list")
        route_introspection.describe("GET", "/widgets", { model = "Widget", operation = "list", fields = {} })
        local after = openapi.encode(openapi.build_document({}))
        assert.is_not_nil(after:find("/widgets", 1, true))
        assert.is_true(before ~= after)
    end)

    it("returns nil, err when building blows up instead of raising, and the caller can audit it", function()
        local original_all = route_introspection.all
        route_introspection.all = function() error("boom: introspection unavailable") end

        local doc, err = openapi.build_document({})
        route_introspection.all = original_all

        assert.is_nil(doc)
        assert.is_not_nil(err)

        -- audit.set_log_path is a process-wide default: save and restore it so later specs
        -- that log without an explicit path keep writing to their expected default file.
        local default_log_path = os.getenv("GUARACI_AUDIT_LOG") or "guaraci_audit.log"
        -- guaraci_random (backed by /dev/urandom) avoids math.random's deterministic,
        -- unseeded sequence in Lua 5.4, which could otherwise collide across process runs.
        local log_path = "tests/tmp_openapi_audit_" .. guaraci_random.hex(8) .. ".log"
        audit.set_log_path(log_path)
        audit.log_error("openapi_build_failed", { error = tostring(err) })
        local fh = io.open(log_path, "r")
        local content = fh:read("*a")
        fh:close()
        os.remove(log_path)
        audit.set_log_path(default_log_path)
        assert.is_not_nil(content:find('"openapi_build_failed"', 1, true))
    end)
end)

describe("api_explorer.openapi.encode", function()
    it("encodes scalars the same way json_util does", function()
        assert.are.equal("null", openapi.encode(nil))
        assert.are.equal("true", openapi.encode(true))
        assert.are.equal("42", openapi.encode(42))
        assert.are.equal('"a\\"b"', openapi.encode('a"b'))
    end)

    it("encodes a plain array without an __omap marker", function()
        assert.are.equal("[1,2,3]", openapi.encode({ 1, 2, 3 }))
    end)
end)
