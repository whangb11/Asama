-- 02_gtable_access.lua
-- 场景：动态名字访问、绕过元表的 raw 访问、遍历全局表
print("=== 02 通过 _G / rawget / rawset 访问 ===")

print("_G == _ENV ?", _G == _ENV)   -- 默认情况下是同一个表

-- 动态名字只能走 _G（语法上的 a.b 需要编译期常量名）
local names = { "alpha", "beta", "gamma" }
for i, n in ipairs(names) do
  _G[n] = i * 100
end
for _, n in ipairs(names) do
  print(n, _G[n], _ENV[n])
end

-- rawget / rawset：绕过 __index / __newindex
rawset(_G, "raw_only", 42)
print("raw_only:", rawget(_G, "raw_only"), rawget(_G, "not_exist"))

-- 函数中通过 _G 间接访问
local function getGlobal(k) return _G[k] end
print("getGlobal('alpha') =", getGlobal("alpha"))

-- _G 自身也是一个全局变量
print("_G._G == _G :", _G._G == _G)

-- 遍历当前所有全局变量
local count = 0
for k, v in pairs(_G) do
  count = count + 1
  if count <= 5 then print("  global key:", k, type(v)) end
end
print("global count ~=", count)

for _, n in ipairs(names) do _G[n] = nil end
_G.raw_only = nil
print("done")