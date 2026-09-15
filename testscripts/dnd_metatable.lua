-- 04_global_metatable.lua
-- 场景：拦截未定义全局变量的读 / 未存在全局变量的写
print("=== 04 给 _G 设置元表 ===")

local log = {}

local mt = {
  __index = function(t, k)
    log[#log + 1] = "READ  " .. tostring(k)
    return rawget(t, k)      -- 不存在的全局返回 nil
  end,
  __newindex = function(t, k, v)
    log[#log + 1] = "WRITE " .. tostring(k) .. " = " .. tostring(v)
    rawset(t, k, v)
  end,
}

local old_mt = getmetatable(_G)
setmetatable(_G, mt)

gv_a = 1                       -- 键不存在 -> 触发 __newindex
local v = gv_a                 -- 键已存在 -> 不触发 __index
local u = undefined_global     -- 键不存在 -> 触发 __index

print("gv_a =", v, " undefined_global =", u)
print("-- 拦截日志 --")
for _, l in ipairs(log) do print("  " .. l) end

setmetatable(_G, old_mt)       -- 复原
gv_a = nil
print("done")