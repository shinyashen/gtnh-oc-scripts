-- ae2_iface:AE2 样板操作公共库(ME/fluid 接口发现、样板读取、条目收集与格式化)
-- 拆分自上游单文件版《样板OC工具箱》内嵌工具中逐字相同的重复实现,行为保持一致。
-- 注:collectSide 采用 pattern-to-fluid 的版本(多一个 oreDict 字段),
--     pattern-merge 不读该字段,无行为差异。
local component = require("component")

local M = {}

-- 十六进制转义(用于 NBT tag 作 key)
function M.hex(s)
    if not s then return nil end
    return (s:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end

-- tag 字段可能以字符串或字节表两种形式给出,统一转成字符串
function M.tagStr(t)
    if t == nil then return nil end
    if type(t) == "string" then return t end
    if type(t) == "table" then
        local o = {}
        for i = 1, #t do o[i] = string.char(tonumber(t[i]) % 256) end
        return table.concat(o)
    end
    return nil
end

-- 把(数字键)表按 key 排序取出来,pairs 无序时的稳定遍历用
function M.sortedKeys(t)
    local k = {}
    if type(t) ~= "table" then return k end
    for n in pairs(t) do
        if type(n) == "number" then k[#k + 1] = n end
    end
    table.sort(k)
    return k
end

function M.numStr(v)
    local n = tonumber(v) or 1
    if n == math.floor(n) then return string.format("%d", math.floor(n)) end
    return tostring(n)
end

-- 条目是否是流体:显式标记 / 有 amount 字段 / 名字像熔融或 fluid 前缀
function M.isFluid(it)
    if it.isFluid == true then return true end
    if it.amount ~= nil then return true end
    local n = tostring(it.name or ""):lower()
    if n:find("molten", 1, true) then return true end
    if n:sub(1, 6) == "fluid." then return true end
    return false
end

-- 条目显示名(截短):取 label,没有则用 name(pattern-merge 用)
function M.brief(it, maxLen)
    local s = tostring(it.label or it.name or "?")
    maxLen = maxLen or 8
    local ok, n = pcall(utf8.len, s)
    if ok and n and n > maxLen then
        local pos = utf8.offset(s, maxLen + 1)
        if pos then s = s:sub(1, pos - 1) .. ".." end
    elseif not ok and #s > maxLen then
        s = s:sub(1, maxLen) .. ".."
    end
    return s
end

-- 找接口:适配器贴 fluid_interface 优先,退回 me_interface
function M.findIface()
    for addr in component.list("fluid_interface") do
        return component.proxy(addr), "fluid_interface"
    end
    for addr in component.list("me_interface") do
        return component.proxy(addr), "me_interface"
    end
    return nil, nil
end

-- 找全部接口(fluid_interface 优先;一个都没有才用 me_interface)
function M.findIfaces()
    local list = {}
    for addr in component.list("fluid_interface") do
        list[#list + 1] = component.proxy(addr)
    end
    if #list == 0 then
        for addr in component.list("me_interface") do
            list[#list + 1] = component.proxy(addr)
        end
    end
    return list
end

-- 找数据库升级(适配器里),重命名/NBT 项写入要用
function M.findDb()
    for addr in component.list("database") do
        return component.proxy(addr)
    end
    return nil
end

-- 接口样板槽位数探测: GTNH 接口为 9/18/27/36 档(NEE 接口升级决定),越界调用会失败。
-- 递增探测 4 次确定档位,按接口地址缓存(接口槽位数运行期内不变)。
local slotCache = {}

function M.patternSlotCount(iface)
    local key = tostring(iface.address or "")
    local cached = slotCache[key]
    if cached then return cached end
    local n = 36
    if not pcall(iface.getInterfacePattern, 36) then
        n = 27
        if not pcall(iface.getInterfacePattern, 27) then
            n = 18
            if not pcall(iface.getInterfacePattern, 18) then
                n = 9
            end
        end
    end
    if key ~= "" then slotCache[key] = n end
    return n
end

-- 列出接口样板槽里已有内容的样板(槽位数按接口档位自适应)
function M.listPatterns(iface)
    local out = {}
    for slot = 1, M.patternSlotCount(iface) do
        local ok, p = pcall(iface.getInterfacePattern, slot)
        if ok and p then out[#out + 1] = { slot = slot, pat = p } end
    end
    return out
end

-- 把样板某一侧(outputs/inputs)转成规整条目列表
function M.collectSide(list)
    local out = {}
    for _, k in ipairs(M.sortedKeys(list)) do
        local it = list[k]
        if type(it) == "table" and next(it) ~= nil then
            local t = M.tagStr(it.tag)
            out[#out + 1] = {
                name = tostring(it.name or ""),
                damage = tonumber(it.damage) or 0,
                size = tonumber(it.size or it.amount) or 1,
                fluid = M.isFluid(it),
                tag = (t and #t > 0) and t or nil,
                label = tostring(it.label or ""),
                hasTag = it.hasTag == true,
                oreDict = tostring(it.oreDict or ""),
            }
        end
    end
    return out
end

return M
