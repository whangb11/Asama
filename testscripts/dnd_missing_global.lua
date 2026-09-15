-- 05_missing_global.lua
-- 场景：读未定义全局返回 nil；错误用法演示
print("=== 05 未定义全局变量 ===")

print("no_such_global =", no_such_global)
print("type:", type(no_such_global))

local function f() return no_such_global end
print("f() =", f())

-- 用 rawget 精确判断“是否存在”（不受 __index 影响）
print("rawget(_G,'no_such_global') =", rawget(_G, "no_such_global"))

-- 拼接 nil：报错
local ok, err = pcall(function()
  local s = "value: " .. no_such_global
  return s
end)
print("concat nil:", ok, err)

-- 调用 nil：报错
local ok2, err2 = pcall(function() return no_such_func() end)
print("call nil:", ok2, err2)

-- 用 false / nil 做区分
g_flag = false
if g_flag then print("true branch") else print("false branch") end
g_flag = nil
print("g_flag is nil now:", g_flag == nil)