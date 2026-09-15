-- 09_stress_test.lua
-- 用法: lua 09_stress_test.lua [NVARS] [NREADS] [NFUNCS] [OUTFILE]
--   NVARS   定义的全局变量个数         默认 2000
--   NREADS  连续全局读改写语句条数     默认 5000
--   NFUNCS  直接访问全局的函数个数     默认 100（受每函数局部变量上限限制）
--   OUTFILE 生成的脚本路径             默认 09_stress_globals.lua

local NVARS   = math.max(tonumber(arg[1]) or 2000, 4)
local NREADS  = tonumber(arg[2]) or 5000
local NFUNCS  = math.min(tonumber(arg[3]) or 100, 150)
local OUTFILE = arg[4] or "dnd_stress_globals.lua"

local function generate()
  local p, n = {}, 0
  local function W(s) n = n + 1; p[n] = s end

  W("-- 自动生成：全局变量压力测试脚本 (Lua 5.4.4)\n")
  W("-- 特点：变量多、语句多、篇幅大，绝大多数操作都是对全局表的直接访问\n")
  W("local t0 = os.clock()\n")
  W("local NVARS, NREADS, NFUNCS = " .. NVARS .. ", " .. NREADS .. ", " .. NFUNCS .. "\n")

  W("\n-- [1] 定义 " .. NVARS .. " 个全局变量（SETTABUP 密集）\n")
  for k = 1, NVARS do W("g_v" .. k .. " = " .. k .. "\n") end

  W("\n-- [2] " .. NREADS .. " 条连续全局读改写语句（GETTABUP/SETTABUP 密集）\n")
  for k = 1, NREADS do
    W("g_acc = (g_acc or 0) + g_v" .. ((k % NVARS) + 1) .. "\n")
  end

  W("\n-- [3] " .. NFUNCS .. " 个函数，函数体直接访问全局变量\n")
  for k = 1, NFUNCS do
    W("local function s_f" .. k .. "(x) return x + g_v"
      .. ((k % NVARS) + 1) .. " - g_v" .. (((k * 7) % NVARS) + 1) .. " end\n")
  end

  W("\n-- [4] 调用全部函数\nlocal acc = 0\n")
  for k = 1, NFUNCS do
    W("acc = acc + s_f" .. k .. "(" .. k .. ")\n")
  end

  W("\n-- [5] 密集循环中的全局访问（每轮 5 次全局操作，共 10 万轮）\n")
  W("local sum = 0\n")
  W("for i = 1, 100000 do\n")
  W("  sum = sum + g_v1 + g_v2 + g_v3\n")
  W("  g_loop = sum\n")
  W("end\n")

  W("\n-- [6] 通过 _G 动态访问（哈希查找慢路径对照）\n")
  W("local sum2 = 0\n")
  W("for i = 1, 10000 do sum2 = sum2 + _G.g_v1 end\n")

  W("\n-- [7] 对照组：先做局部缓存再循环\n")
  W("local v1, v2, v3 = g_v1, g_v2, g_v3\n")
  W("local sum3 = 0\n")
  W("for i = 1, 100000 do sum3 = sum3 + v1 + v2 + v3 end\n")

  W("\nprint(string.format(\n")
  W("  'vars=%d reads=%d funcs=%d | g_acc=%s acc=%d sum=%d sum2=%d sum3=%d | run=%.4fs',\n")
  W("  NVARS, NREADS, NFUNCS, tostring(g_acc), acc, sum, sum2, sum3, os.clock() - t0))\n")

  return table.concat(p)
end

-- ---------- 1) 生成 ----------
local src = generate()
local fh = assert(io.open(OUTFILE, "w"))
fh:write(src)
fh:close()

local _, lineCount = src:gsub("\n", "")
print(string.format("[gen ] %s : %.1f KiB, %d lines", OUTFILE, #src / 1024, lineCount))

-- ---------- 2) 加载 ----------
local t0 = os.clock()
local chunk, err = loadfile(OUTFILE)
if not chunk then error("load failed: " .. tostring(err), 0) end
local t1 = os.clock()

-- ---------- 3) 执行 ----------
local ok, rerr = pcall(chunk)
local t2 = os.clock()
if not ok then error("run failed: " .. tostring(rerr), 0) end

print(string.format("[perf] load=%.4fs  run=%.4fs  total=%.4fs", t1 - t0, t2 - t1, t2 - t0))

-- ---------- 4) 清理生成的全局变量 ----------
for i = 1, NVARS do _G["g_v" .. i] = nil end
_G.g_acc, _G.g_loop = nil, nil