-- Counter stores for middleware_ratelimit.
-- Interface: store.get(key) -> {count, reset_at}|nil, store.set(key, entry), store.incr(key, window, now) -> count, reset_at.
-- Limitation: every request rewrites the whole file (fine for dev/small sites; a sqlite store can replace it).
-- The file store keeps state across CGI processes (one process per request); writes are atomic renames, so
-- concurrent requests can lose an increment but never corrupt the file (limits are approximate under load).
local M = {}

function M.memory()
    local entries = {}
    local store = { kind = "memory" }

    function store.get(key)
        return entries[key]
    end

    function store.set(key, entry)
        entries[key] = entry
    end

    function store.incr(key, window, now)
        local entry = entries[key]
        if entry == nil or now >= entry.reset_at then
            entry = { count = 0, reset_at = now + window }
            entries[key] = entry
        end
        entry.count = entry.count + 1
        return entry.count, entry.reset_at
    end

    return store
end

local function encode_key(key)
    return (tostring(key):sub(1, 128):gsub("[^%w%.:_%-]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

-- Returns entries, or nil, reason when the file exists but cannot be trusted (corrupt/unreadable).
local function load_entries(path, now)
    local entries = {}
    local fh = io.open(path, "r")
    if not fh then
        return entries
    end
    for line in fh:lines() do
        if line ~= "" then
            local key, count, reset_at = line:match("^(%S+)\t(%d+)\t(%d+)$")
            if not key then
                fh:close()
                return nil, "ratelimit_store_corrupt"
            end
            if tonumber(reset_at) > now then
                entries[key] = { count = tonumber(count), reset_at = tonumber(reset_at) }
            end
        end
    end
    fh:close()
    return entries
end

-- Temp files use one of 16 fixed names, so a crash leaves at most 16 leftovers (reused on later writes).
local function save_entries(path, entries)
    local tmp = path .. ".tmp" .. require("guaraci_random").hex(1):sub(2)
    local fh, err = io.open(tmp, "w")
    if not fh then
        return nil, err
    end
    for key, entry in pairs(entries) do
        local ok, write_err = fh:write(key, "\t", entry.count, "\t", entry.reset_at, "\n")
        if not ok then
            fh:close()
            os.remove(tmp)
            return nil, write_err
        end
    end
    local closed, close_err = fh:close()
    if not closed then
        os.remove(tmp)
        return nil, close_err
    end
    local renamed, rename_err = os.rename(tmp, path)
    if not renamed then
        os.remove(tmp)
        return nil, rename_err
    end
    return true
end

function M.file(path)
    local store = { kind = "file", path = path }

    function store.get(key)
        local entries = load_entries(path, os.time())
        return entries and entries[encode_key(key)]
    end

    -- Verifies the location is writable without touching existing counters.
    function store.check()
        local entries, load_err = load_entries(path, os.time())
        if not entries then
            return nil, load_err
        end
        return save_entries(path, entries)
    end

    function store.set(key, entry)
        local entries, load_err = load_entries(path, os.time())
        if not entries then
            return nil, load_err
        end
        entries[encode_key(key)] = entry
        return save_entries(path, entries)
    end

    function store.incr(key, window, now)
        local entries, load_err = load_entries(path, now)
        if not entries then
            error(load_err, 0)
        end
        local encoded = encode_key(key)
        local entry = entries[encoded] or { count = 0, reset_at = now + window }
        entry.count = entry.count + 1
        entries[encoded] = entry
        local ok, err = save_entries(path, entries)
        if not ok then
            error("ratelimit_store_write_failed: " .. tostring(err), 0)
        end
        return entry.count, entry.reset_at
    end

    return store
end

return M
