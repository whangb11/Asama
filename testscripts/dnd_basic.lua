-- 01_basic_global.lua
-- 场景：最基础的全局变量读写
-- 编译后 a = 1 会生成 SETTABUP _ENV "a" 1，读 a 生成 GETTABUP _ENV "a"
print("=== 01 基础全局变量访问 ===")

g_counter = 1
g_name    = "lua-5.4.4"
g_table   = { a = 1, b = 2 }

print("g_counter =", g_counter)
print("g_name    =", g_name)

g_counter = g_counter + 1
print("g_counter =", g_counter)

-- 函数体内访问全局：函数闭包持有同一个 _ENV upvalue
local function bump() g_counter = g_counter + 10 end
bump()
print("after bump:", g_counter)

-- 删除全局变量（写 nil）
g_name = nil
print("g_name after delete:", g_name, rawget(_G, "g_name"))

-- 定义全局函数
function g_add(a, b) return a + b end
print("g_add(2,3) =", g_add(2, 3))
print("_G.g_add   =", _G.g_add)

g_counter, g_table, g_add = nil, nil, nil
print("done")