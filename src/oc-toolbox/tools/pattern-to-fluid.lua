
local component = require("component")
local lib = require("ae2_iface")
local hex, tagStr, sortedKeys, numStr, isFluid = lib.hex, lib.tagStr, lib.sortedKeys, lib.numStr, lib.isFluid
local findIface, listPatterns, collectSide = lib.findIface, lib.listPatterns, lib.collectSide
local patternSlotCount = lib.patternSlotCount
local M = {
    id = "pattern-to-fluid",
    name = "高炉转流体",
    group = "AE2 样板",
    order = 30,
    desc = "把输出的锭换成熔融流体\n1 锭 = 144 mB",
}
local MB_PER_INGOT = 144
local FLUID_PREFIX = "molten."
local FLUID_PREFIX_ALT = "gregtech:molten."
local BEC_MAP = {
    ["entangled_neutronium"] = "molten.neutronium",
    ["entangled_cosmicneutronium"] = "molten.cosmicneutronium",
    ["entangled_bedrockium"] = "molten.bedrockium",
    ["entangled_chromaticglass"] = "molten.chromaticglass",
    ["entangled_celestialtungsten"] = "molten.celestialtungsten",
    ["entangled_infinity"] = "molten.infinity",
    ["entangled_hypogen"] = "molten.hypogen",
    ["entangled_transcendentmetal"] = "molten.transcendentmetal",
    ["entangled_spacetime"] = "molten.spacetime",
    ["entangled_dimshiftedsuperfluid"] = "dimensionallyshiftedsuperfluid",
    ["entangled_phononmedium"] = "phononmedium",
    ["entangled_quarkgluonplasma"] = "quarkgluonplasma",
    ["entangled_time"] = "temporalfluid",
    ["entangled_space"] = "spatialfluid",
    ["entangled_cosmicsolder"] = "boundlesscosmicsolder",
    ["entangled_mhdcsm"] = "magnetohydrodynamicallyconstrainedstarmatter",
    ["entangled_magmatter"] = "molten.magmatter",
    ["entangled_universium"] = "molten.universium",
    ["entangled_eternity"] = "molten.eternity",
}
local function convertEntangled(list)
    local out, log = {}, {}
    for _, e in ipairs(list) do
        local key = tostring(e.name or "")
        local fname = BEC_MAP[key]
        if not fname then
            local short = key:match("^[^:]+:(.+)$")
            if short then fname = BEC_MAP[short] end
        end
        if fname and not e.fluid then
            local ne = {
                name = fname,
                damage = 0,
                size = e.size,
                fluid = true,
                label = "",
                hasTag = false,
            }
            out[#out + 1] = ne
            log[#log + 1] = { kind = "bec", from = e, to = ne }
        else
            out[#out + 1] = e
        end
    end
    return out, log
end
local function brief(it, maxLen)
    local s = tostring(it.label or "")
    if s == "" then
        s = tostring(it.name or "?")
        s = s:gsub("^gregtech:", ""):gsub("^minecraft:", "")
    end
    maxLen = maxLen or 10
    local ok, n = pcall(utf8.len, s)
    if ok and n and n > maxLen then
        local pos = utf8.offset(s, maxLen + 1)
        if pos then s = s:sub(1, pos - 1) .. ".." end
    elseif not ok and #s > maxLen then
        s = s:sub(1, maxLen) .. ".."
    end
    return s
end
local function materialFromLabel(lb)
    lb = tostring(lb or "")
    if not lb:find("[Ii]ngot$") then return nil end
    local mat = lb:gsub("^Hot%s+", "")
    mat = mat:gsub("%s*[Ii]ngot$", "")
    mat = mat:lower()
    mat = mat:gsub("%s+", "")
    if mat == "" then return nil end
    return mat
end
local function ingotMaterial(it, labels)
    local lb0 = tostring(it.label or "")
    if lb0 ~= "" then
        local m0 = materialFromLabel(lb0)
        if m0 then return m0 end
    end
    if labels then
        local key = string.format("%s:%d", tostring(it.name or ""), tonumber(it.damage) or 0)
        local lb = labels[key]
        if lb and lb ~= "" then
            local m1 = materialFromLabel(lb)
            if m1 then return m1 end
        end
    end
    local od = tostring(it.oreDict or "")
    if od ~= "" then
        local m2 = od:match("^ingotHot(%a[%w]*)$") or od:match("^ingot(%a[%w]*)$")
        if m2 then return m2:lower() end
    end
    local n = tostring(it.name or ""):lower()
    local m3 = n:match("([%w_]+)_hot_ingot$") or n:match("([%w_]+)_ingot$")
    if m3 then return m3 end
    return nil
end
local function isIngot(e)
    if e.fluid then return false end
    local lb = tostring(e.label or "")
    if lb:find("[Ii]ngot$") then return true end
    if lb == "" then
        local od = tostring(e.oreDict or "")
        if od:sub(1, 5) == "ingot" then return true end
        local n = tostring(e.name or ""):lower()
        if n:match("_ingot$") or n:match(":ingot") then return true end
    end
    return false
end
local function fluidMaterial(fname)
    local n = tostring(fname or ""):lower()
    local m = n:match("molten[%._]([%w_]+)$")
    if m then return m end
    m = n:match("^fluid%.([%w_]+)$")
    if m then return m end
    return nil
end
local function learnLabels(iface)
    local map = {}
    local f = iface.getItemsInNetwork
    if not f then return map, false end
    local ok, list = pcall(f)
    if not ok or type(list) ~= "table" then return map, false end
    local n = 0
    for _, it in ipairs(list) do
        if type(it) == "table" and it.name then
            local k = string.format("%s:%d", tostring(it.name), tonumber(it.damage) or 0)
            if it.label and tostring(it.label) ~= "" and map[k] == nil then
                map[k] = tostring(it.label)
                n = n + 1
            end
        end
    end
    return map, n > 0
end
local function learnFluidNames(iface)
    local map = {}
    for slot = 1, patternSlotCount(iface) do
        local ok, p = pcall(iface.getInterfacePattern, slot)
        if ok and p then
            for _, list in ipairs({ p.outputs, p.inputs }) do
                for _, k in ipairs(sortedKeys(list)) do
                    local it = list[k]
                    if type(it) == "table" and isFluid(it) then
                        local mat = fluidMaterial(it.name)
                        if mat and map[mat] == nil then
                            map[mat] = tostring(it.name)
                        end
                    end
                end
            end
        end
    end
    return map
end
local function keyOfEntry(e)
    return table.concat({ tostring(e.name or ""), tostring(e.damage or 0), tostring(e.size or 1) }, "|")
end
local function convertOutputs(outs, fluidMap, manual, known, labels)
    local newOuts, log, skipped = {}, {}, {}
    for _, e in ipairs(outs) do
        if e.fluid then
            newOuts[#newOuts + 1] = e
            log[#log + 1] = { kind = "keepFluid", from = e, to = e }
        elseif isIngot(e) then
            local mat = ingotMaterial(e, labels)
            local fname = (manual and manual[entryKey(e)])
                or (known and known[entryKey(e)])
                or (mat and fluidMap[mat]) or nil
            if not fname and mat and not fluidMap[mat] then
                fname = FLUID_PREFIX .. mat
            end
            if fname then
                local n = (tonumber(e.size) or 1) * MB_PER_INGOT
                local ne = {
                    name = fname,
                    damage = 0,
                    size = n,
                    fluid = true,
                    label = "",
                    hasTag = false,
                }
                newOuts[#newOuts + 1] = ne
                log[#log + 1] = { kind = "converted", from = e, to = ne, mat = mat }
            else
                newOuts[#newOuts + 1] = e
                skipped[#skipped + 1] = e
                log[#log + 1] = { kind = "fail", from = e, to = e }
            end
        else
            newOuts[#newOuts + 1] = e
            log[#log + 1] = { kind = "keepOther", from = e, to = e }
        end
    end
    return newOuts, log, skipped
end
local function dumpEntry(it)
    if type(it) ~= "table" then return tostring(it) end
    local ks = {}
    for k in pairs(it) do ks[#ks + 1] = tostring(k) end
    table.sort(ks)
    local parts = {}
    for _, k in ipairs(ks) do
        local v = it[k]
        local vs
        if type(v) == "table" then vs = "<table>" else vs = tostring(v) end
        parts[#parts + 1] = k .. "=" .. vs
    end
    return table.concat(parts, " ")
end
local function writeOne(iface, kind, slot, idx, e)
    local candidates
    if e.fluid then
        local short = e.name
        local long = e.name
        if short:sub(1, 9) == "gregtech:" then
            short = short:sub(10)
        else
            long = "gregtech:" .. short
        end
        candidates = {
            { data = { name = short, size = e.size }, tag = "fluid", label = "size/短名" },
            { data = { name = long, size = e.size }, tag = "fluid", label = "size/长名" },
            { data = { name = short, amount = e.size }, tag = "fluid", label = "amount/短名" },
            { data = { name = long, amount = e.size }, tag = "fluid", label = "amount/长名" },
        }
    else
        local d = { name = e.name, size = e.size }
        if e.damage and e.damage ~= 0 then d.damage = e.damage end
        if e.tag then d.tag = e.tag end
        candidates = { { data = d, tag = "item", label = "item" } }
    end
    local lastErr = nil
    for _, c in ipairs(candidates) do
        pcall(function()
            if kind == "out" then
                return iface.setInterfacePatternOutput(slot, idx, c.data, c.tag)
            else
                return iface.setInterfacePatternInput(slot, idx, c.data, c.tag)
            end
        end)
        os.sleep(0.15)
        local okR, pat = pcall(iface.getInterfacePattern, slot)
        if okR and pat then
            local list = (kind == "out") and pat.outputs or pat.inputs
            local got = list and list[idx]
            local gotName = got and tostring(got.name) or nil
            if gotName == e.name then
                return true, c.label
            end
            if gotName == tostring(c.data.name) then
                return true, c.label
            end
            if gotName == nil then
                return true, c.label .. "(未回读)"
            end
            lastErr = string.format("%s: 回读是 %s", c.label, gotName)
        else
            return true, c.label .. "(未回读)"
        end
    end
    return false, lastErr or "四种写法都试过了"
end
local function writePattern(iface, slot, outs, ins, dry)
    local notes = {}
    local function put(kind, list)
        for idx, e in ipairs(list) do
            if dry then
                notes[#notes + 1] = string.format("%s#%d 跳过(预览)", kind, idx)
            else
                local ok, how = writeOne(iface, kind, slot, idx, e)
                if not ok then
                    return false, string.format("%s 第 %d 项失败：%s", kind, idx, tostring(how))
                end
                notes[#notes + 1] = string.format("%s#%d=%s", kind, idx, tostring(how))
            end
            os.sleep(0)
        end
        return true
    end
    local ok1, err1 = put("in", ins)
    if not ok1 then return false, err1 end
    local ok2, err2 = put("out", outs)
    if not ok2 then return false, err2 end
    if not dry then
        local chk = iface.getInterfacePattern(slot)
        if chk then
            for kind, want in pairs({ ["in"] = #ins, ["out"] = #outs }) do
                local list = (kind == "in") and chk.inputs or chk.outputs
                local n = 0
                if list then for _ in pairs(list) do n = n + 1 end end
                if n > want then
                    notes[#notes + 1] = string.format("警告：%s 还有 %d 项多余的老条目（%d 应为 %d）",
                        kind, n - want, n, want)
                end
            end
        end
    end
    return true, table.concat(notes, " "), true
end
local function fmtEntry(e)
    return string.format("%s ×%s", brief(e, 10), numStr(e.size))
end
function M.run(ctx, args)
    args = args or {}
    local verbose, dry = false, false
    for _, a in ipairs(args) do
        local t = tostring(a)
        if t == "--verbose" or t == "-v" then verbose = true end
        if t == "--dry" then dry = true end
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
                title = "没有找到任何样板", footer = "在ME接口中放入样板",
            })
        else
            ctx.write("没有找到任何样板")
        end
        return false
    end
    ctx.clear()
    ctx.write(string.format("高炉转流体 · 共 %d 个样板，逐个检查", #found))
    ctx.write(string.rep("-", 60))
    local fluidMap = learnFluidNames(iface)
    local labels, hasLabels = learnLabels(iface)
    do
        local nl = 0
        for _ in pairs(labels) do nl = nl + 1 end
        ctx.write(string.format("从 ME 网络读到 %d 个物品显示名", nl))
    end
    local nOk, nSkip, nFail = 0, 0, 0
    local devlog = {}
    for _, it in ipairs(found) do
        local outs = collectSide(it.pat.outputs)
        local ins0 = collectSide(it.pat.inputs)
        local ins, becLog = convertEntangled(ins0)
        local newOuts, log, skipped = convertOutputs(outs, fluidMap, nil, nil, labels)
        for _, r in ipairs(becLog) do log[#log + 1] = r end
        local changed = false
        for _, r in ipairs(log) do
            if r.kind == "converted" or r.kind == "bec" then changed = true end
        end
        if not changed then
            nSkip = nSkip + 1
            ctx.write(string.format("槽 %d: 跳过（没认出锭）", it.slot))
            local rawOut = it.pat.outputs
            local shown = 0
            for _, k in ipairs(sortedKeys(rawOut)) do
                if shown < 3 then
                    shown = shown + 1
                    ctx.write("    原始输出" .. k .. ": " .. dumpEntry(rawOut[k]))
                end
            end
            if shown == 0 then
                ctx.write("    （这个样板读不到任何输出）")
            end
        else
            ctx.write(string.format("槽 %d:", it.slot))
            for _, r in ipairs(log) do
                if r.kind == "converted" then
                    ctx.write(string.format("   %s → %s", fmtEntry(r.from), fmtEntry(r.to)))
                elseif r.kind == "bec" then
                    ctx.write(string.format("   纠缠容器 %s → %s", fmtEntry(r.from), fmtEntry(r.to)))
                elseif r.kind == "fail" then
                    ctx.write(string.format("   !! %s 认不出流体，保持原样", fmtEntry(r.from)))
                end
            end
            local ok, err = writePattern(iface, it.slot, newOuts, ins, dry)
            if ok then
                ctx.write("   [成功] 已写入 " .. it.slot .. " 槽")
                nOk = nOk + 1
            else
                ctx.write("   [失败] " .. tostring(err))
                nFail = nFail + 1
            end
            devlog[#devlog + 1] = string.format("槽%d %s", it.slot, ok and "OK" or tostring(err))
        end
        os.sleep(0)
    end
    ctx.write(string.rep("-", 60))
    ctx.write(string.format("完成：转换成功 %d 个，无锭跳过 %d 个，失败 %d 个",
        nOk, nSkip, nFail))
    if nFail > 0 then
        ctx.write("失败的样板原因如下：")
        for _, l in ipairs(devlog) do
            if l:find("OK") == nil then ctx.write("   " .. l) end
        end
    end
    ctx.write("")
    if ctx.select then
        ctx.select({ { label = "好了", value = 1 } }, {
            title = string.format("高炉转流体：成功 %d / 跳过 %d / 失败 %d", nOk, nSkip, nFail),
            footer = "失败的会写回原样，可以再跑一次",
        })
    else
        ctx.write("按任意键返回")
    end
    return nFail == 0
end
return M
