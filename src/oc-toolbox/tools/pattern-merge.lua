
local component = require("component")
local lib = require("ae2_iface")
local hex, tagStr, sortedKeys, numStr, isFluid = lib.hex, lib.tagStr, lib.sortedKeys, lib.numStr, lib.isFluid
local brief, findIface, findDb, listPatterns, collectSide =
    lib.brief, lib.findIface, lib.findDb, lib.listPatterns, lib.collectSide
local patternSlotCount = lib.patternSlotCount
local fs = require("filesystem")
local M = {
    id = "pattern-merge",
    name = "样板合并",
    group = "AE2 样板",
    order = 20,
    desc = "把接口里所有样板合成一个",
}
local function keyOf(e)
    return table.concat({
        e.name,
        tostring(e.damage or 0),
        e.tag and hex(e.tag) or "",
        e.fluid and "F" or "I",
    }, "|")
end
local function mergeList(parts)
    local map, order = {}, {}
    for _, part in ipairs(parts) do
        for _, e in ipairs(part) do
            local k = keyOf(e)
            if not map[k] then
                map[k] = {
                    name = e.name, damage = e.damage, size = e.size,
                    fluid = e.fluid, tag = e.tag, label = e.label, hasTag = e.hasTag,
                    from = { 1 },
                }
                order[#order + 1] = k
            else
                map[k].size = map[k].size + e.size
            end
        end
    end
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = map[k] end
    return out
end
local function countTagged(list)
    local n = 0
    for _, e in ipairs(list) do
        if e.tag or e.nbt then n = n + 1 end
    end
    return n
end
local function writePattern(ctx, iface, slot, outs, ins)
    local unknown = 0
    for _, list in ipairs({ outs, ins }) do
        for _, e in ipairs(list) do
            if e.hasTag and not e.tag and not e.nbt then unknown = unknown + 1 end
        end
    end
    if unknown > 0 then
        return false, string.format("有 %d 项带 NBT 读不到内容，请先给它们设个名字", unknown)
    end
    local db, dbSlot = nil, 1
    local function ensureDb()
        if not db then db = findDb() end
        return db
    end
    local function put(kind, list)
        for idx, e in ipairs(list) do
            local ok
            if e.nbt then
                local d = ensureDb()
                if not d then
                    return false, "有按名字重建的项，但找不到数据库升级（要插电脑机箱）"
                end
                d.set(dbSlot, e.name, e.damage or 0, e.nbt)
                if d.get and d.get(dbSlot) == nil then
                    return false, string.format("数据库第 %d 槽没写进去", dbSlot)
                end
                if kind == "out" then
                    ok = iface.setInterfacePatternOutput(slot, idx, d.address, dbSlot, e.size or 1)
                else
                    ok = iface.setInterfacePatternInput(slot, idx, d.address, dbSlot, e.size or 1)
                end
                dbSlot = dbSlot + 1
            else
                local d
                if e.fluid then
                    d = { name = e.name, size = e.size }
                else
                    d = { name = e.name, size = e.size }
                    if e.damage ~= 0 then d.damage = e.damage end
                end
                if e.tag then d.tag = e.tag end
                local t = e.fluid and "fluid" or "item"
                if kind == "out" then
                    ok = iface.setInterfacePatternOutput(slot, idx, d, t)
                else
                    ok = iface.setInterfacePatternInput(slot, idx, d, t)
                end
            end
            if not ok then
                return false, string.format("第 %d 项（%s）写入失败", idx,
                    e.label ~= "" and e.label or e.name)
            end
            os.sleep(0)
        end
        return true
    end
    local ok1, err1 = put("out", outs)
    if not ok1 then return false, err1 end
    local ok2, err2 = put("in", ins)
    if not ok2 then return false, err2 end
    local chk = iface.getInterfacePattern(slot)
    if not chk then return false, "写完了但回读不到样板" end
    local nIn, nOut = 0, 0
    if chk.inputs then for _ in pairs(chk.inputs) do nIn = nIn + 1 end end
    if chk.outputs then for _ in pairs(chk.outputs) do nOut = nOut + 1 end end
    if nOut < #outs or nIn < #ins then
        return false, string.format("回读数量对不上：写进 输出%d/输入%d，读回 输出%d/输入%d",
            #outs, #ins, nOut, nIn)
    end
    return true
end
function M.run(ctx, args)
    args = args or {}
    local dry, toSlot = false, nil
    for _, a in ipairs(args) do
        local s = tostring(a)
        if s == "--dry" then
            dry = true
        else
            local n = s:match("^%-%-to=(%d+)$")
            if n then toSlot = tonumber(n) end
        end
    end
    local iface, ifaceKind = findIface()
    if not iface then
        if ctx.select then
            ctx.select({ { label = "知道了", value = 1 } }, {
                title = "找不到ME接口",
                footer = "检查适配器是否紧贴ME接口",
            })
        else
            ctx.write("找不到ME接口")
        end
        return false
    end
    local found = listPatterns(iface)
    if #found == 0 then
        if ctx.select then
            ctx.select({ { label = "知道了", value = 1 } }, {
                title = "没有找到任何样板",
                footer = "在ME接口中放入样板",
            })
        else
            ctx.write("没有找到任何样板")
        end
        return false
    end
    local allOuts, allIns = {}, {}
    for _, it in ipairs(found) do
        allOuts[#allOuts + 1] = collectSide(it.pat.outputs)
        allIns[#allIns + 1] = collectSide(it.pat.inputs)
    end
    local mergedOuts = mergeList(allOuts)
    local mergedIns = mergeList(allIns)
    local lines = {}
    lines[#lines + 1] = string.format("找到 %d 个样板，合并后：", #found)
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("输出 %d 项", #mergedOuts)
    for _, e in ipairs(mergedOuts) do
        lines[#lines + 1] = string.format("   %s ×%s", brief(e, 12), numStr(e.size))
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("输入 %d 项", #mergedIns)
    for _, e in ipairs(mergedIns) do
        lines[#lines + 1] = string.format("   %s ×%s", brief(e, 12), numStr(e.size))
    end
    local nTag = countTagged(mergedOuts) + countTagged(mergedIns)
    if nTag > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("注意：有 %d 项带 NBT（改名/附魔等）", nTag)
        lines[#lines + 1] = "  需要配置里 allowItemStackNBTTags = true 才能保住"
        lines[#lines + 1] = "  没开的话这些物品会变回原名"
    end
    if dry then
        for _, l in ipairs(lines) do ctx.write(l) end
        return true
    end
    if ctx.select then
        local items = {}
        for _, l in ipairs(lines) do
            items[#items + 1] = { label = l, value = "__info__" }
        end
        table.insert(items, 1, { label = "▶ 开始合并" .. (toSlot and ("（写到槽 " .. toSlot .. "）") or ""), value = "__go__" })
        table.insert(items, 2, { label = "取消", value = "__cancel__" })
        local pick
        repeat
            pick = ctx.select(items, {
                title = "样板合并 · 第 1 步：确认要合并的内容",
                footer = "点「▶ 开始合并」继续   ↑↓ 移动   Q 返回菜单",
            })
            if pick == nil then return true end
        until pick ~= "__info__"
        if pick ~= "__go__" then return true end
    else
        for _, l in ipairs(lines) do ctx.write(l) end
    end
    if ctx.select and ctx.prompt then
        while true do
            local items2 = {
                { label = "▶ 名字都不用改，继续", value = "__next__" },
            }
            for _, e in ipairs(mergedOuts) do
                items2[#items2 + 1] = {
                    label = "输出  " .. brief(e, 10) .. "  ×" .. numStr(e.size),
                    desc = "显示名：" .. (e.label ~= "" and e.label or "(无)"),
                    value = { item = e, side = "输出" },
                }
            end
            for _, e in ipairs(mergedIns) do
                items2[#items2 + 1] = {
                    label = "输入  " .. brief(e, 10) .. "  ×" .. numStr(e.size),
                    desc = "显示名：" .. (e.label ~= "" and e.label or "(无)"),
                    value = { item = e, side = "输入" },
                }
            end
            local pick = ctx.select(items2, {
                title = "样板合并 · 第 2 步：要改哪个物品的显示名？（不想改就直接继续）",
                footer = "点物品改名   点第一项继续    ↑↓ 移动   Q 取消",
            })
            if pick == nil then return true end
            if pick == "__next__" then break end
            local e = pick.item
            local cur = (e.label ~= "" and e.label) or nil
            local nm = ctx.prompt(
                string.format("%s「%s」的新显示名", pick.side, e.label ~= "" and e.label or e.name),
                cur,
                "直接打字（只支持英文数字）  Enter 确定  Q 取消  Backspace 删除")
            if nm and nm ~= "" then
                local esc = nm:gsub("\\", "\\\\"):gsub('"', '\\"')
                e.nbt = '{display:{Name:"' .. esc .. '"}}'
                e.label = nm
            end
        end
    end
    if not toSlot then
        if ctx.select then
            local slots = {}
            for slot = 1, patternSlotCount(iface) do
                local ok, p = pcall(iface.getInterfacePattern, slot)
                if ok and p ~= nil then
                    slots[#slots + 1] = {
                        label = string.format("槽 %d", slot),
                        desc = "（有样板，合并后内容会被覆盖）",
                        value = slot,
                    }
                end
            end
            if #slots == 0 then
                return false, "一个可写的槽都没有（空槽要先塞占位样板）"
            end
            toSlot = ctx.select(slots, {
                title = "样板合并 · 第 2 步：合并结果写到哪个槽",
                footer = "只能选已有样板的槽（空槽要先塞占位样板）   Q 取消",
            })
            if not toSlot then return true end
        else
            local ans = ctx.ask("写到哪个槽（数字）> ", "")
            toSlot = tonumber(ans or "")
            if not toSlot then return false end
        end
    end
    local ok, err = writePattern(ctx, iface, toSlot, mergedOuts, mergedIns)
    if ctx.select then
        if ok then
            ctx.select({ { label = "好的", value = 1 } }, {
                title = string.format("合并完成：已写入槽 %d", toSlot),
                footer = string.format("输出 %d 项 / 输入 %d 项   去游戏里点开看看吧", #mergedOuts, #mergedIns),
            })
        else
            ctx.select({ { label = "知道了", value = 1 } }, {
                title = "合并失败",
                footer = tostring(err),
            })
        end
    else
        ctx.write(ok and "合并完成" or ("失败：" .. tostring(err)))
    end
    return ok
end
return M
