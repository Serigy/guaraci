local router_v2 = require("router_v2")
local route_introspection = require("route_introspection")

local function noop(req, res) return res end

describe("route_introspection", function()
    before_each(function()
        router_v2.clear()
        route_introspection.clear()
    end)

    after_each(function()
        router_v2.clear()
        route_introspection.clear()
    end)

    it("round-trips a manual descriptor with the exact shape", function()
        local descriptor = {
            model = "Product",
            operation = "get",
            fields = { { name = "title", type = "string", required = true } },
            requires_tenant = true
        }
        assert.is_true(route_introspection.describe("GET", "/products/:id", descriptor))
        local got = route_introspection.get("GET", "/products/:id")
        assert.are.equal("Product", got.model)
        assert.are.equal("get", got.operation)
        assert.are.equal(true, got.requires_tenant)
        assert.are.equal("title", got.fields[1].name)
    end)

    it("is case/method sensitive and keyed on method+pattern", function()
        route_introspection.describe("GET", "/products", { model = "Product", operation = "list" })
        assert.is_nil(route_introspection.get("POST", "/products"))
        assert.is_nil(route_introspection.get("GET", "/other"))
    end)

    it("overwrites the descriptor on a second describe for the same key", function()
        route_introspection.describe("GET", "/products", { model = "Product", operation = "list" })
        route_introspection.describe("GET", "/products", { model = "Product", operation = "list", fields = {} })
        local got = route_introspection.get("GET", "/products")
        assert.is_not_nil(got.fields)
    end)

    it("clear() empties both the descriptor map and the catalog view", function()
        router_v2.get("/products", noop)
        route_introspection.describe("GET", "/products", { model = "Product", operation = "list" })
        route_introspection.clear()
        router_v2.clear()
        assert.are.equal(0, #route_introspection.all())
        assert.is_nil(route_introspection.get("GET", "/products"))
    end)

    it("lists static and :id routes, generated and ad-hoc, in fixed method/registration order", function()
        router_v2.post("/products", noop)
        router_v2.get("/products", noop)
        router_v2.get("/products/:id", noop)
        router_v2.get("/adhoc/:name", noop)

        route_introspection.describe("GET", "/products", { model = "Product", operation = "list" })
        route_introspection.describe("GET", "/products/:id", { model = "Product", operation = "get" })
        route_introspection.describe("POST", "/products", { model = "Product", operation = "create" })

        local all = route_introspection.all()
        assert.are.equal(4, #all)

        -- Fixed method order: GET before POST regardless of registration order.
        assert.are.equal("GET", all[1].method)
        assert.are.equal("/products", all[1].pattern)
        assert.are.equal("Product", all[1].descriptor.model)

        assert.are.equal("GET", all[2].method)
        assert.are.equal("/products/:id", all[2].pattern)
        assert.are.equal("id", all[2].param_names[1])
        assert.are.equal("get", all[2].descriptor.operation)

        assert.are.equal("GET", all[3].method)
        assert.are.equal("/adhoc/:name", all[3].pattern)
        assert.are.equal("name", all[3].param_names[1])
        assert.is_nil(all[3].descriptor)

        assert.are.equal("POST", all[4].method)
        assert.are.equal("create", all[4].descriptor.operation)
    end)

    it("never executes a route handler to build the catalog", function()
        local called = false
        router_v2.get("/products", function() called = true end)
        route_introspection.all()
        assert.is_false(called)
    end)

    it("does not retain stale descriptors or duplicates across two simulated dev reloads", function()
        router_v2.get("/products", noop)
        route_introspection.describe("GET", "/products", { model = "Product", operation = "list" })
        assert.are.equal(1, #route_introspection.all())

        -- Simulated reload #1: guaraci dev clears router_v2 + route_introspection, then re-runs app.lua.
        router_v2.clear()
        route_introspection.clear()
        router_v2.get("/products", noop)
        route_introspection.describe("GET", "/products", { model = "Product", operation = "list" })
        assert.are.equal(1, #route_introspection.all())

        -- Simulated reload #2.
        router_v2.clear()
        route_introspection.clear()
        router_v2.get("/products", noop)
        route_introspection.describe("GET", "/products", { model = "Product", operation = "list" })
        local all = route_introspection.all()
        assert.are.equal(1, #all)
        assert.is_not_nil(all[1].descriptor)
    end)
end)
