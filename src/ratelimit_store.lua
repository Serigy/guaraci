-- Counter stores for middleware_ratelimit.
-- Interface: store.get(key) -> {count, reset_at}|nil, store.set(key, entry), store.incr(key, window, now) -> count, reset_at.
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

local function load_entries(path, now)
    local entries = {}
    local fh = io.open(path, "r")
    if not fh then
        return entries
    end
    for line in fh:lines() do
        local key, count, reset_at = line:match("^(%S+)\t(%d+)\t(%d+)$")
        if key and tonumber(reset_at) > now then
            entries[key] = { count = tonumber(count), reset_at = tonumber(reset_at) }
        end
    end
    fh:close()
    return entries
end

local function save_entries(path, entries)
    local tmp = path .. ".tmp" .. require("guaraci_random").hex(4)
    local fh, err = io.open(tmp, "w")
    if not fh then
        return nil, err
    end
    for key, entry in pairs(entries) do
        fh:write(key, "\t", entry.count, "\t", entry.reset_at, "\n")
    end
    fh:close()
    local ok, rename_err = os.rename(tmp, path)
    if not ok then
        os.remove(tmp)
        return nil, rename_err
    end
    return true
end

function M.file(path)
    local store = { kind = "file", path = path }

    function store.get(key)
        return load_entries(path, os.time())[encode_key(key)]
    end

    function store.set(key, entry)
        local entries = load_entries(path, os.time())
        entries[encode_key(key)] = entry
        return save_entries(path, entries)
    end

    function store.incr(key, window, now)
        local entries = load_entries(path, now)
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
