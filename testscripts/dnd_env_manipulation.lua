-- 08_env_manipulation.lua
-- 场景：把 _ENV 当成普通局部变量来观察 / 替换
print("=== 08 _ENV 赋值、传参与 upvalue 观察 ===")

-- 1. _ENV 就是个普通局部变量
local print_orig = print
do
  local _ENV = { print = print_orig, a = 1, b = 2 }
  print("a + b =", a + b)
  c = 99
  print("c =", c)
end

-- 2. 观察编译结果：全局访问全部落到 _ENV 这个 upvalue 上
local chunk = load("local x = 1; y = x + 1; return y")
print("--- debug.getupvalue ---")
local i = 1
while true do
  local name, val = debug.getupvalue(chunk, i)
  if not name then break end
  print(string.format("  upvalue[%d] = %s (%s)", i, name, type(val)))
  i = i + 1
end
chunk()                       -- y 被写到 _G
print("_G.y =", _G.y)
_G.y = nil

-- 3. 用 debug.setupvalue 替换 _ENV
local env = setmetatable({}, { __index = _G })
local f = load("return version_marker")
debug.setupvalue(f, 1, env)
env.version_marker = "ENV-OK"
print("替换 _ENV 后:", f())

-- 4. 多个闭包共享同一个 _ENV
local function outer()
  local _ENV = { tag = "shared" }
  local function inner1() return tag end
  local function inner2() tag = "modified"; return tag end
  return inner1, inner2
end
local i1, i2 = outer()
local r1, r2, r3 = i1(), i2(), i1()
print(r1, r2, r3)             -- shared  modified  modified