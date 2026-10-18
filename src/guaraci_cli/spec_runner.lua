-- Minimal busted-compatible harness and runner shared by `guaraci test` and the core suite.
local M = {}

local harness = {}

local base_assert = assert
local suites = {}
local suite_stack = {}

local function current_suite()
    return suite_stack[#suite_stack]
end

local function fail(message)
    error(message or "assertion failed", 3)
end

local function make_assert_table()
    local out = {}

    out.is_true = function(value, message)
        if value ~= true then
            fail(message or ("expected true, got " .. tostring(value)))
        end
    end

    out.is_false = function(value, message)
        if value ~= false then
            fail(message or ("expected false, got " .. tostring(value)))
        end
    end

    out.is_nil = function(value, message)
        if value ~= nil then
            fail(message or ("expected nil, got " .. tostring(value)))
        end
    end

    out.is_not_nil = function(value, message)
        if value == nil then
            fail(message or "expected non-nil value")
        end
    end

    out.are = {
        equal = function(expected, actual, message)
            if expected ~= actual then
                fail(message or ("expected=" .. tostring(expected) .. ", actual=" .. tostring(actual)))
            end
        end
    }

    return setmetatable(out, {
        __call = function(_, ...)
            return base_assert(...)
        end
    })
end

function harness.install_globals()
    local previous = {
        describe = _G.describe,
        it = _G.it,
        before_each = _G.before_each,
        after_each = _G.after_each,
        assert = _G.assert
    }

    _G.assert = make_assert_table()

    _G.describe = function(name, fn)
        if type(name) ~= "string" or type(fn) ~= "function" then
            error("describe(name, fn) invalido")
        end

        local suite = {
            name = name,
            tests = {},
            before_each = nil,
            after_each = nil
        }

        suites[#suites + 1] = suite
        suite_stack[#suite_stack + 1] = suite
        fn()
        suite_stack[#suite_stack] = nil
    end

    _G.it = function(name, fn)
        local suite = current_suite()
        if not suite then
            error("it() deve ser usado dentro de describe()")
        end

        if type(name) ~= "string" or type(fn) ~= "function" then
            error("it(name, fn) invalido")
        end

        suite.tests[#suite.tests + 1] = {
            name = name,
            fn = fn
        }
    end

    _G.before_each = function(fn)
        local suite = current_suite()
        if not suite then
            error("before_each() deve ser usado dentro de describe()")
        end

        if type(fn) ~= "function" then
            error("before_each(fn) invalido")
        end

        suite.before_each = fn
    end

    _G.after_each = function(fn)
        local suite = current_suite()
        if not suite then
            error("after_each() deve ser usado dentro de describe()")
        end

        if type(fn) ~= "function" then
            error("after_each(fn) invalido")
        end

        suite.after_each = fn
    end

    return function()
        _G.describe = previous.describe
        _G.it = previous.it
        _G.before_each = previous.before_each
        _G.after_each = previous.after_each
        _G.assert = previous.assert
    end
end

function harness.reset()
    suites = {}
    suite_stack = {}
end

function harness.get_suites()
    return suites
end


M.harness = harness

local function run_suite(suite)
    local failures = 0

    io.write("\n" .. suite.name .. "\n")

    for i = 1, #suite.tests do
        local test = suite.tests[i]

        if suite.before_each then
            local ok_before, before_err = pcall(suite.before_each)
            if not ok_before then
                io.write("  [FAIL] " .. test.name .. " (before_each): " .. tostring(before_err) .. "\n")
                failures = failures + 1
                goto continue
            end
        end

        local ok_test, test_err = pcall(test.fn)
        if not ok_test then
            io.write("  [FAIL] " .. test.name .. ": " .. tostring(test_err) .. "\n")
            failures = failures + 1
        else
            io.write("  [OK] " .. test.name .. "\n")
        end

        if suite.after_each then
            local ok_after, after_err = pcall(suite.after_each)
            if not ok_after then
                io.write("  [FAIL] " .. test.name .. " (after_each): " .. tostring(after_err) .. "\n")
                failures = failures + 1
            end
        end

        ::continue::
    end

    return failures
end

function M.run(spec_modules)
    local busted = M.harness
    busted.reset()
    local restore = busted.install_globals()

    local load_failures = 0
    for i = 1, #spec_modules do
        local mod = spec_modules[i]
        local ok, err = pcall(require, mod)
        if not ok then
            io.write("[FAIL] load spec " .. mod .. ": " .. tostring(err) .. "\n")
            load_failures = load_failures + 1
        end
    end

    if load_failures > 0 then
        restore()
        io.write("TOTAL FAILURES: " .. tostring(load_failures) .. "\n")
        return false
    end

    local loaded_suites = busted.get_suites()
    local failures = 0

    for i = 1, #loaded_suites do
        failures = failures + run_suite(loaded_suites[i])
    end

    restore()
    if failures > 0 then
        io.write("\nTOTAL FAILURES: " .. tostring(failures) .. "\n")
        return false
    end

    io.write("\nALL SPECS PASSED\n")
    return true
end

return M
