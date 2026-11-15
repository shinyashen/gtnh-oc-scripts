
local component = require("component")
local lib = require("ae2_iface")
local findIface, listPatterns = lib.findIface, lib.listPatterns
local M = {
    id = "shield-gas",
    name = "保护气替换",
    group = "AE2 样板",
    order = 40,
    desc = "给样板加保护气、换保护气、或者清掉保护气",
}
local GASES = {
    { id = "oganesson", cn = "鿫", amount = 100 },
    { id = "xenon",     cn = "氙", amount = 250 },
    { id = "krypton",   cn = "氪", amount = 400 },
    { id = "neon",      cn = "氖", amount = 550 },
    { id = "radon",     cn = "氡", amount = 700 },
    { id = "argon",     cn = "氩", amount = 850 },
    { id = "helium",    cn = "氦", amount = 1000 },
    { id = "nitrogen",  cn = "氮", amount = 1000 },
}
local BY_ID = {}
for _, g in ipairs(GASES) do
    BY_ID[g.id] = g
end
local function shortName(name)
    local nm = tostring(name or ""):lower()
    local s = nm:match("^[^:]+:(.+)$")
    if s then return s end
    return nm
end
local function gasOf(e)
    return BY_ID[shortName(e.name)]
end
local function countInputs(p)
    local n, maxIdx = 0, 0
    for idx in pairs(p.inputs or {}) do
        n = n + 1
        if idx > maxIdx then maxIdx = idx end
    end
    return n, maxIdx
end
function M.run(ctx, args)
    local iface, ifaceKind = findIface()
    if not iface then
        if ctx.select then
            ctx.select({ { label = "知道了", value = 1 } }, {
                title = "找不到ME接口",
                footer = "检查适配器是否紧贴方块",
            })
        else
            ctx.write("找不到ME接口")
        end
        return false
    end
    local patterns = listPatterns(iface)
    if #patterns == 0 then
        if ctx.select then
            ctx.select({ { label = "知道了", value = 1 } }, {
                title = "接口里没有样板", footer = "先把样板插进接口",
            })
        else
            ctx.write("接口里没有样板")
        end
        return false
    end
    local items = {}
    for _, g in ipairs(GASES) do
        items[#items + 1] = {
            label = g.cn .. "  " .. g.id,
            desc = "需要 " .. g.amount,
            value = { kind = "set", gas = g },
        }
    end
    items[#items + 1] = {
        label = "清除保护气",
        desc = "把样板里的保护气删掉",
        value = { kind = "clear" },
    }
    local pick
    if ctx.select then
        pick = ctx.select(items, {
            title = string.format("保护气：选一种（接口里 %d 个样板）", #patterns),
            footer = "点一行选中   ↑↓ 移动   Enter 确定   Q 返回",
        })
    else
        for i, it in ipairs(items) do
            ctx.write(string.format("  %d. %s  %s", i, it.label, it.desc))
        end
        local ans = ctx.ask("选哪个（数字）> ", "")
        local n = tonumber(ans or "")
        if n and items[n] then pick = items[n].value end
    end
    if not pick then return true end
    local gas = pick.gas
    local clearMode = (pick.kind == "clear")
    ctx.clear()
    ctx.write(clearMode and "清除保护气" or ("换成 " .. gas.cn .. " " .. gas.id))
    ctx.write(string.rep("-", 50))
    ctx.write(string.format("共 %d 个样板", #patterns))
    ctx.write("")
    local nAdd, nChange, nClear, nSkip, nFail = 0, 0, 0, 0, 0
    for _, item in ipairs(patterns) do
        local slot = item.slot
        local p = item.pat
        local nIn = countInputs(p)
        if nIn == 0 then
            nSkip = nSkip + 1
        else
            local gasIdx = nil
            for idx, e in pairs(p.inputs) do
                if gasOf(e) then gasIdx = idx end
            end
            if clearMode then
                if gasIdx then
                    local ok = iface.clearInterfacePatternInput(slot, gasIdx)
                    if ok then
                        nClear = nClear + 1
                        ctx.write(string.format("槽 %d: 清除保护气（第 %d 项）", slot, gasIdx))
                    else
                        nFail = nFail + 1
                        ctx.write(string.format("槽 %d: 清除失败", slot))
                    end
                else
                    nSkip = nSkip + 1
                end
            else
                if gasIdx then
                    local ok = iface.setInterfacePatternInput(slot, gasIdx,
                        { name = gas.id, size = gas.amount }, "fluid")
                    if ok then
                        nChange = nChange + 1
                        ctx.write(string.format("槽 %d: %s → %s×%d", slot, gas.cn, gas.id, gas.amount))
                    else
                        nFail = nFail + 1
                        ctx.write(string.format("槽 %d: 改失败", slot))
                    end
                else
                    local _, maxIdx = countInputs(p)
                    local ok = iface.setInterfacePatternInput(slot, maxIdx + 1,
                        { name = gas.id, size = gas.amount }, "fluid")
                    if ok then
                        nAdd = nAdd + 1
                        ctx.write(string.format("槽 %d: 加 %s×%d（第 %d 项）", slot, gas.id, gas.amount, maxIdx + 1))
                    else
                        nFail = nFail + 1
                        ctx.write(string.format("槽 %d: 加失败", slot))
                    end
                end
            end
        end
        os.sleep(0)
    end
    ctx.write("")
    ctx.write(string.format("完成：加 %d，改 %d，清 %d，跳过 %d，失败 %d",
        nAdd, nChange, nClear, nSkip, nFail))
    if ctx.select then
        ctx.select({ { label = "好了", value = 1 } }, {
            title = string.format("保护气：加 %d / 改 %d / 清 %d / 跳过 %d / 失败 %d",
                nAdd, nChange, nClear, nSkip, nFail),
            footer = "可以再去游戏里看看样板",
        })
    end
    return nFail == 0
end
return M
