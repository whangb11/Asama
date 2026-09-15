-- 07_load_env.lua
-- 场景：load 的 env 参数、动态可见性、沙箱化加载
print("=== 07 load 与自定义环境 ===")

-- 1. 默认 env = _G，且是动态可见的
local f = load("return g_version")
print("before set:", f())
g_version = "5.4.4"
print("after  set:", f())

-- 2. 指定 env
local env = { greet = "hello" }
local g = load("return greet .. ' ' .. name", "chunk", "t", env)
env.name = "world"
print(g())

-- 3. 沙箱：读可见全局，写被拒绝
local sandbox    = {}
local sandbox_mt = {
  __index    = _G,
  __newindex = function(_, k)
    error("sandbox: write to '" .. tostring(k) .. "' denied", 2)
  end,
}
local env2 = setmetatable(sandbox, sandbox_mt)

local h = load("local r = string.upper('abc'); return r", "safe", "t", env2)
print("safe chunk:", h())

local w, lerr = load("x = 1", "unsafe", "t", env2)
print("load ok:", w ~= nil, lerr)
local ok, err = pcall(w)
print("sandbox write:", ok, err)

-- 4. load 出来的 chunk，第一个 upvalue 就是 _ENV
local chunk = load("return _ENV.marker")
print("upvalue name:", debug.getupvalue(chunk, 1))
print("call:", chunk())

-- 5. 语法错误在 load 阶段就能捕获
local bad, msg = load("return 1 +")
print("syntax err:", bad, msg)