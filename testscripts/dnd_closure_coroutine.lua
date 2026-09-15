-- 06_closure_coroutine.lua
-- 场景：多个闭包共享 _ENV；协程中访问全局；局部缓存 vs 直接全局访问
print("=== 06 闭包 / 协程中的全局变量 ===")

g_shared = 0

local function makeIncrementer(n)
  return function()
    g_shared = g_shared + n
    return g_shared
  end
end
local inc1, inc2 = makeIncrementer(1), makeIncrementer(10)
local a, b, c = inc1(), inc2(), inc1()   -- 避免 print 参数求值顺序影响结果
print(a, b, c, g_shared)                 -- 1  11  12  12

-- 协程中访问全局
local co = coroutine.create(function()
  g_shared = g_shared + 100
  local snapshot = g_shared
  coroutine.yield(snapshot)
  g_shared = g_shared * 2
  return g_shared
end)
print("resume:", coroutine.resume(co))
print("mid   :", g_shared)
print("resume:", coroutine.resume(co))
print("end   :", g_shared)

-- 局部缓存 vs 每次全局查找
g_data = { v = 1 }
local N = 200000
local function slow()
  local s = 0
  for _ = 1, N do s = s + g_data.v end   -- 每轮一次 GETTABUP
  return s
end
local function fast()
  local d = g_data                       -- 只查一次，之后走寄存器
  local s = 0
  for _ = 1, N do s = s + d.v end
  return s
end
local t0 = os.clock(); slow(); local t1 = os.clock(); fast(); local t2 = os.clock()
print(string.format("slow(直接全局) %.4fs  fast(局部缓存) %.4fs", t1 - t0, t2 - t1))

g_shared, g_data = nil, nil