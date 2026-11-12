-- Pure-Lua 32-bit bitwise operations polyfill (LuaJIT 'bit' API compatible)
local bit = {}
local MOD = 2^32

local function tobit(x)
    x = x % MOD
    if x >= 0x80000000 then
        x = x - MOD
    end
    return math.floor(x)
end

bit.tobit = tobit

function bit.tohex(x, n)
    n = n or 8
    local up = false
    if n < 0 then
        up = true
        n = -n
    end
    x = x % MOD
    local fmt = "%0" .. n .. (up and "X" or "x")
    return string.format(fmt, x):sub(-n)
end

function bit.bnot(a)
    return tobit(-1 - tobit(a))
end

local function bitop(a, b, oper)
    a, b = a % MOD, b % MOD
    local res, p = 0, 1
    while a > 0 or b > 0 do
        local ra, rb = a % 2, b % 2
        if oper(ra, rb) then
            res = res + p
        end
        a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
    end
    return tobit(res)
end

function bit.band(a, b, ...)
    local res = bitop(a, b, function(x, y) return x == 1 and y == 1 end)
    for i = 1, select("#", ...) do
        res = bitop(res, select(i, ...), function(x, y) return x == 1 and y == 1 end)
    end
    return res
end

function bit.bor(a, b, ...)
    local res = bitop(a, b, function(x, y) return x == 1 or y == 1 end)
    for i = 1, select("#", ...) do
        res = bitop(res, select(i, ...), function(x, y) return x == 1 or y == 1 end)
    end
    return res
end

function bit.bxor(a, b, ...)
    local res = bitop(a, b, function(x, y) return x ~= y end)
    for i = 1, select("#", ...) do
        res = bitop(res, select(i, ...), function(x, y) return x ~= y end)
    end
    return res
end

function bit.lshift(a, n)
    n = n % 32
    return tobit((a % MOD) * (2 ^ n))
end

function bit.rshift(a, n)
    n = n % 32
    return tobit(math.floor((a % MOD) / (2 ^ n)))
end

function bit.arshift(a, n)
    n = n % 32
    local x = tobit(a)
    if x < 0 then
        return tobit(math.floor(x / (2 ^ n)))
    else
        return bit.rshift(x, n)
    end
end

function bit.rol(a, n)
    n = n % 32
    a = a % MOD
    return tobit(a * (2 ^ n) + math.floor(a / (2 ^ (32 - n))))
end

function bit.ror(a, n)
    n = n % 32
    a = a % MOD
    return tobit(math.floor(a / (2 ^ n)) + a * (2 ^ (32 - n)))
end

function bit.bswap(a)
    a = a % MOD
    local b1 = a % 256
    local b2 = math.floor(a / 256) % 256
    local b3 = math.floor(a / 65536) % 256
    local b4 = math.floor(a / 16777216) % 256
    return tobit(b1 * 16777216 + b2 * 65536 + b3 * 256 + b4)
end

return bit
