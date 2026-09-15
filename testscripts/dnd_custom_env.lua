-- 03_custom_env.lua
-- 场景：local _ENV = xxx，实现沙箱、只读环境、环境链
print("=== 03 自定义 _ENV 环境 ===")

-- 1. 私有沙箱：不污染真实全局表
local sandbox = {}
do
  local _ENV = sandbox          -- 从此处起，x/y/z/add 全部写进 sandbox
  x = 1
  y = 2
  z = x + y
  function add(a, b) return a + b end   -- sandbox.add
end
print("sandbox.x,y,z:", sandbox.x, sandbox.y, sandbox.z)
print("_G.x =", rawget(_G, "x"))        -- nil，真实全局未被污染
print("sandbox.add(3,4) =", sandbox.add(3, 4))

-- 2. 只读环境：读回退到 _G，写直接报错
local base = setmetatable({ version = "5.4.4" }, { __index = _G })
local ro = setmetatable({}, {
  __index = base,
  __newindex = function(_, k)
    error("attempt to write readonly global '" .. tostring(k) .. "'", 2)
  end,
})
do
  local _ENV = ro
  print("version =", version)                       -- 来自 base
  print("string.upper('abc') =", string.upper("abc")) -- 回退到 _G
  local ok, err = pcall(function() newvar = 1 end)
  print("write to readonly env:", ok, err)
end

-- 3. 多级环境链
local L1 = setmetatable({ a = 1 }, { __index = _G })
local L2 = setmetatable({ b = 2 }, { __index = L1 })
local L3 = setmetatable({ c = 3 }, { __index = L2 })
do
  local _ENV = L3
  print("a,b,c =", a, b, c)
end

-- 4. _ENV 是 upvalue，多个闭包共享同一环境
local function makeReader(env)
  local _ENV = env
  return function() return token end   -- 每次调用都查 env.token
end
local r1 = makeReader({ token = "T1" })
local r2 = makeReader({ token = "T2" })
print(r1(), r2())