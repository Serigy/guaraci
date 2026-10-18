-- Unpredictable ids. Lua 5.3 and LuaJIT start math.random from a fixed seed, so every CGI process would
-- draw the same sequence. Strong ids need /dev/urandom; otherwise math.random is seeded once per process
-- (that fallback only avoids identical sequences and is not cryptographic).
local M = {}

local seeded = false

local function seed_once()
    if seeded then
        return
    end
    seeded = true
    local seed = os.time() * 1000003 + math.floor(os.clock() * 1000000)
    -- Table addresses vary with ASLR and allocation history; mix several. This is NOT cryptographic:
    -- strong ids require /dev/urandom.
    for _ = 1, 4 do
        local addr = tostring({}):match("0x(%x+)") or tostring({}):match("(%x+)$")
        seed = seed * 31 + (tonumber(addr or "0", 16) or 0) % 1000003
    end
    seed = seed + #tostring(print) + (tonumber((tostring(print):match("0x(%x+)") or "0"), 16) or 0) % 65521
    math.randomseed(seed % 2147483647)
    for _ = 1, 8 do
        math.random()
    end
end

-- Returns n random bytes as a string.
function M.bytes(n)
    local fh = io.open("/dev/urandom", "rb")
    if fh then
        local data = fh:read(n)
        fh:close()
        if data and #data == n then
            return data
        end
    end
    seed_once()
    local out = {}
    for i = 1, n do
        out[i] = string.char(math.random(0, 255))
    end
    return table.concat(out)
end

function M.hex(n)
    return (M.bytes(n):gsub(".", function(c)
        return string.format("%02x", c:byte())
    end))
end

-- Uniform-enough integer in [lo, hi] (hi - lo < 2^24).
function M.int(lo, hi)
    local b = M.bytes(4)
    local value = b:byte(1) * 16777216 + b:byte(2) * 65536 + b:byte(3) * 256 + b:byte(4)
    return lo + value % (hi - lo + 1)
end

return M
