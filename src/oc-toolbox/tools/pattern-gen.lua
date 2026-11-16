
local component = require("component")
local lib = require("ae2_iface")
local findIfaces, findDb = lib.findIfaces, lib.findDb

-- ==== 通道样板(2.9 新样板类型: 只有输入无输出) ====
-- 检测接口里的红/蓝通道样板,生成 NAC 电路样板时整组替换为通道引用。
-- 类型判据(GTNH OC 驱动 ConverterPattern): outputs 为空 + isCraftable==false + inputs>=1
--   (合成样板 isCraftable=true 被排除;空白样板被 inputs>=1 排除)
-- 写死两种内容(wiki 旧方案),写了其他内容的通道样板一律不认:
--   红板(命名) = 5 种改名光学贴片 x32 + 光学电路基板 x4   (32:32:32:32:32:4)
--   蓝板(未命名) = 5 种原名光学贴片 x32                    (32:32:32:32:32)
local OPTICAL_CHIP_ITEM = "gregtech:gt.metaitem.03"

-- 物品身份 = name + damage, 命名/未命名维度用 hasTag 区分(三元组)
-- 通道内容项的命名状态来自实际 NBT(hasTag); 配方数据(RECIPES)的命名项用 rename 标记表达,
-- 两边统一按规范化后的命名状态对齐
local function hasTagOf(e)
    if e.hasTag ~= nil then return e.hasTag == true end
    return e.rename == true
end

local function triKey(e)
    return tostring(e.name) .. "|" .. tostring(e.damage or 0) .. "|" .. (hasTagOf(e) and "T" or "F")
end

local function isRedChannel(inputs)
    if #inputs ~= 6 then return false end
    local nChip, nBase = 0, 0
    for _, e in ipairs(inputs) do
        local s = tonumber(e.size) or 0
        if e.hasTag and s == 32 and tostring(e.name) == OPTICAL_CHIP_ITEM then
            nChip = nChip + 1
        elseif s == 4 and e.hasTag then
            nBase = nBase + 1
        else
            return false
        end
    end
    return nChip == 5 and nBase == 1
end

local function isBlueChannel(inputs)
    if #inputs ~= 5 then return false end
    for _, e in ipairs(inputs) do
        if tostring(e.name) ~= OPTICAL_CHIP_ITEM then return false end
        if (tonumber(e.size) or 0) ~= 32 or e.hasTag then return false end
    end
    return true
end

local function findChannelPatterns(ifaces)
    local out = { red = nil, blue = nil }
    for _, iface in ipairs(ifaces) do
        for slot = 1, lib.patternSlotCount(iface) do
            local ok, pat = pcall(iface.getInterfacePattern, slot)
            if ok and type(pat) == "table" and type(pat.inputs) == "table" and #pat.inputs >= 1
                and not (pat.outputs and next(pat.outputs) ~= nil)
                and pat.isCraftable == false then
                -- tag 是引用通道样板的前提(完整 NBT 由 config allowItemStackNBTTags 提供)
                local entry = { slot = slot, iface = iface, pat = pat, tagOk = pat.tag ~= nil }
                if not out.red and isRedChannel(pat.inputs) then
                    out.red = entry
                elseif not out.blue and isBlueChannel(pat.inputs) then
                    out.blue = entry
                end
            end
        end
    end
    return out
end

-- 用通道样板引用替换配方里与其内容成同一整数倍 k 的项组(引用xk = 内容xk)
-- 命中则改写 w.ins 并返回 true;三元组集合/统一倍数对不上则不动(保持改名写入)
local function replaceWithChannel(w, ch)
    if not ch or not ch.tagOk then return false end
    local pat = ch.pat
    local need = {}
    for _, e in ipairs(pat.inputs) do
        local k = triKey(e)
        need[k] = (need[k] or 0) + (tonumber(e.size) or 0)
    end
    local got = {}
    for _, e in ipairs(w.ins) do
        if not e.fluid then
            local k = triKey(e)
            if need[k] then got[k] = (got[k] or 0) + (tonumber(e.size) or 0) end
        end
    end
    local k = nil
    for key, n in pairs(need) do
        local g = got[key] or 0
        if g == 0 then return false end
        local kk = g / n
        if kk ~= math.floor(kk) or kk < 1 then return false end
        if k == nil then k = kk elseif k ~= kk then return false end
    end
    if k == nil then return false end
    local kept = {}
    for _, e in ipairs(w.ins) do
        if e.fluid or not need[triKey(e)] then
            kept[#kept + 1] = e
        end
    end
    kept[#kept + 1] = {
        name = tostring(pat.name),
        damage = tonumber(pat.damage) or 0,
        size = k,
        tag = pat.tag,
        channelRef = true,
        chSlot = ch.slot,
        chCount = k,
    }
    w.ins = kept
    return true
end

local function applyChannelReplacement(list, channels)
    if not channels.red and not channels.blue then return list end
    for _, w in ipairs(list) do
        replaceWithChannel(w, channels.red)
        replaceWithChannel(w, channels.blue)
    end
    return list
end

-- ==== 通道样板部分结束 ====

-- ==== 框架切割液选择 ====
-- NAC 切割仓(纳米精度切割仓)的框架切割配方各有两种可选切割液(中文维基在线 NEI 数据库实测,
-- 共 29 条切割配方; wiki 旧方案只写了其中一种)。RECIPES 数据里写死的是默认项(opts[1]),
-- 用户选择另一项时按 每框架用量 x 框架数 替换对应切割液流体。
local FRAME_CUTTING_FLUIDS = {
    ["miscutils:blockFrameGtCelestialTungsten"] = {
        { name = "grade6purifiedwater", label = "紫外辐照水（六级净化水）", perFrame = 250 },
        { name = "grade5purifiedwater", label = "极温净化水（五级净化水）", perFrame = 250 },
    },
    ["miscutils:blockFrameGtHypogen"] = {
        { name = "grade7purifiedwater", label = "去杂脱气水（七级净化水）", perFrame = 500 },
        { name = "grade8purifiedwater", label = "理想微粒水（八级净化水）", perFrame = 250 },
    },
    ["miscutils:blockFrameGtMagmatter"] = {
        { name = "grade8purifiedwater", label = "理想微粒水（八级净化水）", perFrame = 500 },
        { name = "dimensionallyshiftedsuperfluid", label = "维度偏移超流体", perFrame = 100 },
    },
}

-- 切割液选择交互(参考改名询问): GUI 用 select, CLI 打印编号
local function askCuttingFluid(ctx, w, frameName, opts, frameCount)
    local items = {}
    for k, opt in ipairs(opts) do
        items[#items + 1] = {
            label = opt.label,
            desc = string.format("%dL x %d 框架 = %dL%s",
                opt.perFrame, frameCount, opt.perFrame * frameCount,
                k == 1 and "（当前默认）" or ""),
            value = opt,
        }
    end
    if ctx.select then
        return ctx.select(items, {
            title = string.format("%s：框架切割液（%d 框架）", w.tag or "样板", frameCount),
            footer = "框架: " .. frameName .. "   Q = 保持默认",
        })
    end
    for i, it in ipairs(items) do
        ctx.write(string.format("  %d. %s（%dL x %d）", i, it.label, it.perFrame, frameCount))
    end
    local ans = ctx.ask("切割液选哪个（数字，回车=默认）> ", "1")
    local n = tonumber(ans or "")
    if n and opts[n] then return opts[n] end
    return nil
end

-- 扫描配方里的框架项, 逐框架询问切割液; 选非默认项时替换对应切割液流体
local function applyCuttingFluidChoice(list, ctx)
    for _, w in ipairs(list) do
        local frameCount = {}
        for _, e in ipairs(w.ins) do
            if FRAME_CUTTING_FLUIDS[e.name] and not e.fluid then
                frameCount[e.name] = (frameCount[e.name] or 0) + (tonumber(e.size) or 0)
            end
        end
        for fname, count in pairs(frameCount) do
            local opts = FRAME_CUTTING_FLUIDS[fname]
            local pick = askCuttingFluid(ctx, w, fname, opts, count)
            if pick and pick.name ~= opts[1].name then
                local kept = {}
                for _, e in ipairs(w.ins) do
                    if not (e.fluid and e.name == opts[1].name) then
                        kept[#kept + 1] = e
                    end
                end
                kept[#kept + 1] = { name = pick.name, size = pick.perFrame * count, fluid = true, label = pick.label }
                w.ins = kept
            end
        end
    end
end

-- ==== 框架切割液部分结束 ====

local M = {
    id = "pattern-gen",
    name = "样板生成",
    group = "AE2 样板",
    order = 1,
    desc = "NAC / 神锻等离子 / 夸克 / 磁物质",
}
local RECIPES = {
    {
        name = "皮米电路",
        out = {
            { name = "dreamcraft:PikoCircuit", damage = 0, size = 1 },
        },
        ins = {
            { name = "gregtech:gt.metaitem.01", damage = 29979, size = 16, label = "Thin Radox Polymer Sheet" },
            { name = "miscutils:blockFrameGtCelestialTungsten", damage = 0, size = 2, label = "Celestial Tungsten Frame Box" },
            { name = "miscutils:itemScrewAstralTitanium", damage = 0, size = 4, label = "Astral Titanium Screw" },
            { name = "gregtech:gt.metaitem.02", damage = 18974, size = 1, label = "Superconductor Base UEV Casing" },
            { name = "miscutils:itemPlateRhugnor", damage = 0, size = 2, label = "Rhugnor Plate" },
            { name = "gregtech:gt.metaitem.03", damage = 32157, size = 2, label = "Optical Mainframe" },
            { name = "gregtech:gt.metaitem.03", damage = 32269, size = 8, label = "Opto Power IC" },
            { name = "molten.kevlar", size = 288, fluid = true, label = "Molten Kevlar" },
            { name = "bartworks:gt.bwMetaGeneratedscrew", damage = 10110, size = 2, label = "Enriched Naquadah Alloy Screw" },
            { name = "miscutils:itemBoltRhugnor", damage = 0, size = 8, label = "Rhugnor Bolt" },
            { name = "spatialfluid", size = 250, fluid = true, label = "Spatially Enlarged Fluid" },
            { name = "gregtech:gt.metaitem.03", damage = 32728, size = 4, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.02", damage = 19154, size = 64, label = "Fine Proto-Halkonite Steel Wire" },
            { name = "gregtech:gt.metaitem.01", damage = 26581, size = 32, label = "Transcendent Metal Bolt" },
            { name = "dimensionallyshiftedsuperfluid", size = 80, fluid = true, label = "Dimensionally Shifted Superfluid" },
            { name = "grade6purifiedwater", size = 500, fluid = true, label = "Grade 6 Water" },
            { name = "lubricant", size = 640, fluid = true, label = "Lubricant" },
            { name = "gregtech:gt.blockmachines", damage = 11430, size = 8, label = "1x Infinity Wire" },
            { name = "molten.mutatedlivingsolder", size = 2304, fluid = true, label = "Mutated Living Solder" },
            { name = "ic2uumatter", size = 8000, fluid = true, label = "UU-Matter" },
            { name = "molten.precious metals alloy", size = 1152, fluid = true, label = "Molten Precious Metals Alloy" },
            { name = "gregtech:gt.metaitem.03", damage = 32181, size = 32, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.03", damage = 32178, size = 32, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.03", damage = 32179, size = 32, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.03", damage = 32184, size = 32, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.03", damage = 32180, size = 32, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.03", damage = 32181, size = 32, label = "Optical SMD Capacitor" },
            { name = "gregtech:gt.metaitem.03", damage = 32179, size = 32, label = "Optical SMD Diode" },
            { name = "gregtech:gt.metaitem.03", damage = 32184, size = 32, label = "Optical SMD Inductor" },
            { name = "gregtech:gt.metaitem.03", damage = 32180, size = 32, label = "Optical SMD Transistor" },
            { name = "gregtech:gt.metaitem.03", damage = 32178, size = 32, label = "Optical SMD Resistor" },
        },
    },
    {
        name = "量子电路",
        out = {
            { name = "dreamcraft:QuantumCircuit", damage = 0, size = 1 },
        },
        ins = {
            { name = "bartworks:gt.bwMetaGeneratedfoil", damage = 10112, size = 32, label = "Shirabon Foil" },
            { name = "miscutils:blockFrameGtHypogen", damage = 0, size = 2, label = "Hypogen Frame Box" },
            { name = "gregtech:gt.metaitem.01", damage = 27147, size = 4, label = "Six-Phased Copper Screw" },
            { name = "gregtech:gt.metaitem.02", damage = 18149, size = 1, label = "Cream Casing" },
            { name = "dreamcraft:PikoCircuit", damage = 0, size = 2, label = "Pico Circuit" },
            { name = "miscutils:itemScrewQuantum", damage = 0, size = 2, label = "Quantum Screw" },
            { name = "bartworks:gt.bwMetaGeneratedplate", damage = 10111, size = 2, label = "Metastable Oganesson Plate" },
            { name = "bartworks:gt.bwMetaGeneratedbolt", damage = 10111, size = 8, label = "Metastable Oganesson Bolt" },
            { name = "gregtech:gt.metaitem.03", damage = 32271, size = 8, label = "Zepto Power IC" },
            { name = "bartworks:gt.bwMetaGeneratedwireFine", damage = 10106, size = 4, label = "Fine Tairitsu Wire" },
            { name = "gregtech:gt.metaitem.02", damage = 19190, size = 8, label = "Fine Churitsu Wire" },
            { name = "gregtech:gt.metaitem.02", damage = 19189, size = 4, label = "Fine Shijima Wire" },
            { name = "gregtech:gt.metaitem.03", damage = 32179, size = 64, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.03", damage = 32178, size = 64, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.03", damage = 32181, size = 64, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.03", damage = 32180, size = 64, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.03", damage = 32184, size = 64, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.02", damage = 19154, size = 64, label = "Fine Proto-Halkonite Steel Wire" },
            { name = "gregtech:gt.metaitem.01", damage = 26134, size = 64, label = "Superconductor Base UMV Bolt" },
            { name = "gregtech:gt.blockmachines", damage = 2606, size = 8, label = "1x SpaceTime Wire" },
            { name = "molten.mutatedlivingsolder", size = 4608, fluid = true, label = "Mutated Living Solder" },
            { name = "lubricant", size = 1280, fluid = true, label = "Lubricant" },
            { name = "ic2uumatter", size = 16000, fluid = true, label = "UU-Matter" },
            { name = "molten.sixphasedcopper", size = 144, fluid = true, label = "Molten Six-Phased Copper" },
            { name = "exciteddtec", size = 1000, fluid = true, label = "Excited D.T. Exotic Catalyst" },
            { name = "molten.radoxpoly", size = 288, fluid = true, label = "Molten Radox Polymer" },
            { name = "spatialfluid", size = 500, fluid = true, label = "Spatially Enlarged Fluid" },
            { name = "dimensionallyshiftedsuperfluid", size = 80, fluid = true, label = "Dimensionally Shifted Superfluid" },
            { name = "grade7purifiedwater", size = 1000, fluid = true, label = "Grade 7 Water" },
            { name = "dimensionallytranscendentresidue", size = 2000, fluid = true, label = "Dimensionally Transcendent Residue" },
            { name = "gregtech:gt.metaitem.03", damage = 32728, size = 8, rename = true, label = "qq3" },
            { name = "gregtech:gt.metaitem.03", damage = 32181, size = 64, label = "Optical SMD Capacitor" },
            { name = "gregtech:gt.metaitem.03", damage = 32178, size = 64, label = "Optical SMD Resistor" },
            { name = "gregtech:gt.metaitem.03", damage = 32179, size = 64, label = "Optical SMD Diode" },
            { name = "gregtech:gt.metaitem.03", damage = 32184, size = 64, label = "Optical SMD Inductor" },
            { name = "gregtech:gt.metaitem.03", damage = 32180, size = 64, label = "Optical SMD Transistor" },
        },
    },
}
local ELEMENTS = {
    { kind = "dust", cn = "铍", en = "beryllium", weight = 2, reg = "gregtech:gt.metaitem.01", meta = 2008, cell = "gregtech:gt.metaitem.01", cellMeta = 31008 },
    { kind = "dust", cn = "锔", en = "curium", weight = 10, reg = "miscutils:itemDustCurium", meta = 2, cell = "miscutils:itemCellPlasmaCurium", cellMeta = 0 },
    { kind = "dust", cn = "铈", en = "cerium", weight = 2, reg = "gregtech:gt.metaitem.01", meta = 2065, cell = "gregtech:gt.metaitem.01", cellMeta = 31065 },
    { kind = "dust", cn = "铝", en = "aluminium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2019, cell = "gregtech:gt.metaitem.01", cellMeta = 31019 },
    { kind = "dust", cn = "铪", en = "hafnium", weight = 6, reg = "bartworks:gt.bwMetaGenerateddust", meta = 11000, cell = "miscutils:itemCellPlasmaHafnium", cellMeta = 0 },
    { kind = "dust", cn = "镨", en = "praseodymium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2066, cell = "gregtech:gt.metaitem.01", cellMeta = 31066 },
    { kind = "dust", cn = "钠", en = "sodium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2017, cell = "gregtech:gt.metaitem.01", cellMeta = 31017 },
    { kind = "dust", cn = "砷", en = "arsenic", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2039, cell = "gregtech:gt.metaitem.01", cellMeta = 31039 },
    { kind = "dust", cn = "锶", en = "strontium", weight = 2, reg = "gregtech:gt.metaitem.01", meta = 2044, cell = "gregtech:gt.metaitem.01", cellMeta = 31044 },
    { kind = "dust", cn = "钕", en = "neodymium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2067, cell = "gregtech:gt.metaitem.01", cellMeta = 31067 },
    { kind = "dust", cn = "钛", en = "titanium", weight = 10, reg = "gregtech:gt.metaitem.01", meta = 2028, cell = "gregtech:gt.metaitem.01", cellMeta = 31028 },
    { kind = "dust", cn = "钡", en = "barium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2063, cell = "gregtech:gt.metaitem.01", cellMeta = 31063 },
    { kind = "dust", cn = "镓", en = "gallium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2037, cell = "gregtech:gt.metaitem.01", cellMeta = 31037 },
    { kind = "dust", cn = "锂", en = "lithium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2006, cell = "gregtech:gt.metaitem.01", cellMeta = 31006 },
    { kind = "dust", cn = "铌", en = "niobium", weight = 10, reg = "gregtech:gt.metaitem.01", meta = 2047, cell = "gregtech:gt.metaitem.01", cellMeta = 31047 },
    { kind = "dust", cn = "钒", en = "vanadium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2029, cell = "gregtech:gt.metaitem.01", cellMeta = 31029 },
    { kind = "dust", cn = "碳", en = "carbon", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2010, cell = "gregtech:gt.metaitem.01", cellMeta = 31010 },
    { kind = "dust", cn = "陨铁", en = "meteoriciron", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2340, cell = "gregtech:gt.metaitem.01", cellMeta = 31340 },
    { kind = "dust", cn = "铷", en = "rubidium", weight = 2, reg = "gregtech:gt.metaitem.01", meta = 2043, cell = "gregtech:gt.metaitem.01", cellMeta = 31043 },
    { kind = "dust", cn = "铕", en = "europium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2070, cell = "gregtech:gt.metaitem.01", cellMeta = 31070 },
    { kind = "dust", cn = "钯", en = "palladium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2052, cell = "gregtech:gt.metaitem.01", cellMeta = 31052 },
    { kind = "dust", cn = "铜", en = "copper", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2035, cell = "gregtech:gt.metaitem.01", cellMeta = 31035 },
    { kind = "dust", cn = "阿迪特", en = "ardite", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2382, cell = "gregtech:gt.metaitem.01", cellMeta = 31382 },
    { kind = "dust", cn = "镍", en = "nickel", weight = 10, reg = "gregtech:gt.metaitem.01", meta = 2034, cell = "gregtech:gt.metaitem.01", cellMeta = 31034 },
    { kind = "dust", cn = "硅", en = "silicon", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2020, cell = "gregtech:gt.metaitem.01", cellMeta = 31020 },
    { kind = "dust", cn = "钍-232", en = "thorium232", weight = 6, reg = "bartworks:gt.bwMetaGenerateddust", meta = 30, cell = "miscutils:itemCellPlasmaThorium232", cellMeta = 0 },
    { kind = "dust", cn = "钌", en = "ruthenium", weight = 6, reg = "bartworks:gt.bwMetaGenerateddust", meta = 64, cell = "miscutils:itemCellPlasmaRuthenium", cellMeta = 0 },
    { kind = "dust", cn = "锗", en = "germanium", weight = 2, reg = "miscutils:itemDustGermanium", meta = 28, cell = "miscutils:itemCellPlasmaGermanium", cellMeta = 0 },
    { kind = "dust", cn = "钴", en = "cobalt", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2033, cell = "gregtech:gt.metaitem.01", cellMeta = 31033 },
    { kind = "dust", cn = "锡", en = "tin", weight = 10, reg = "gregtech:gt.metaitem.01", meta = 2057, cell = "gregtech:gt.metaitem.01", cellMeta = 31057 },
    { kind = "dust", cn = "铼", en = "rhenium", weight = 2, reg = "miscutils:itemDustRhenium", meta = 31, cell = "miscutils:itemCellPlasmaRhenium", cellMeta = 0 },
    { kind = "dust", cn = "铥", en = "thulium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2076, cell = "gregtech:gt.metaitem.01", cellMeta = 31076 },
    { kind = "dust", cn = "锆", en = "zirconium", weight = 6, reg = "bartworks:gt.bwMetaGenerateddust", meta = 3, cell = "miscutils:itemCellPlasmaZirconium", cellMeta = 0 },
    { kind = "dust", cn = "铀-235", en = "uranium235", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2097, cell = "gregtech:gt.metaitem.01", cellMeta = 31097 },
    { kind = "dust", cn = "镥", en = "lutetium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2078, cell = "gregtech:gt.metaitem.01", cellMeta = 31078 },
    { kind = "dust", cn = "碘", en = "iodine", weight = 6, reg = "bartworks:gt.bwMetaGenerateddust", meta = 11012, cell = "miscutils:itemCellPlasmaIodine", cellMeta = 0 },
    { kind = "dust", cn = "铑", en = "rhodium", weight = 6, reg = "bartworks:gt.bwMetaGenerateddust", meta = 78, cell = "miscutils:itemCellPlasmaRhodium", cellMeta = 0 },
    { kind = "dust", cn = "钬", en = "holmium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2074, cell = "gregtech:gt.metaitem.01", cellMeta = 31074 },
    { kind = "dust", cn = "铟", en = "indium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2056, cell = "gregtech:gt.metaitem.01", cellMeta = 31056 },
    { kind = "dust", cn = "钷", en = "promethium", weight = 2, reg = "gregtech:gt.metaitem.01", meta = 2068, cell = "gregtech:gt.metaitem.01", cellMeta = 31068 },
    { kind = "dust", cn = "铊", en = "thallium", weight = 2, reg = "miscutils:itemDustThallium", meta = 41, cell = "miscutils:itemCellPlasmaThallium", cellMeta = 0 },
    { kind = "dust", cn = "铀-238", en = "uranium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2098, cell = "gregtech:gt.metaitem.01", cellMeta = 31098 },
    { kind = "dust", cn = "钇", en = "yttrium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2045, cell = "gregtech:gt.metaitem.01", cellMeta = 31045 },
    { kind = "dust", cn = "戴斯", en = "desh", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2884, cell = "gregtech:gt.metaitem.01", cellMeta = 31884 },
    { kind = "dust", cn = "钆", en = "gadolinium", weight = 2, reg = "gregtech:gt.metaitem.01", meta = 2071, cell = "gregtech:gt.metaitem.01", cellMeta = 31071 },
    { kind = "dust", cn = "锌", en = "zinc", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2036, cell = "gregtech:gt.metaitem.01", cellMeta = 31036 },
    { kind = "dust", cn = "钽", en = "tantalum", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2080, cell = "gregtech:gt.metaitem.01", cellMeta = 31080 },
    { kind = "dust", cn = "银", en = "silver", weight = 10, reg = "gregtech:gt.metaitem.01", meta = 2054, cell = "gregtech:gt.metaitem.01", cellMeta = 31054 },
    { kind = "dust", cn = "镝", en = "dysprosium", weight = 2, reg = "gregtech:gt.metaitem.01", meta = 2073, cell = "gregtech:gt.metaitem.01", cellMeta = 31073 },
    { kind = "dust", cn = "金", en = "gold", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2086, cell = "gregtech:gt.metaitem.01", cellMeta = 31086 },
    { kind = "dust", cn = "锑", en = "antimony", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2058, cell = "gregtech:gt.metaitem.01", cellMeta = 31058 },
    { kind = "dust", cn = "钨", en = "tungsten", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2081, cell = "gregtech:gt.metaitem.01", cellMeta = 31081 },
    { kind = "dust", cn = "镧", en = "lanthanum", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2064, cell = "gregtech:gt.metaitem.01", cellMeta = 31064 },
    { kind = "dust", cn = "磷", en = "phosphorus", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2021, cell = "gregtech:gt.metaitem.01", cellMeta = 31021 },
    { kind = "dust", cn = "铽", en = "terbium", weight = 1, reg = "gregtech:gt.metaitem.01", meta = 2072, cell = "gregtech:gt.metaitem.01", cellMeta = 31072 },
    { kind = "dust", cn = "镁", en = "magnesium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2018, cell = "gregtech:gt.metaitem.01", cellMeta = 31018 },
    { kind = "dust", cn = "锰", en = "manganese", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2031, cell = "gregtech:gt.metaitem.01", cellMeta = 31031 },
    { kind = "dust", cn = "镅", en = "americium", weight = 10, reg = "gregtech:gt.metaitem.01", meta = 2103, cell = "gregtech:gt.metaitem.01", cellMeta = 31103 },
    { kind = "dust", cn = "铒", en = "erbium", weight = 2, reg = "gregtech:gt.metaitem.01", meta = 2075, cell = "gregtech:gt.metaitem.01", cellMeta = 31075 },
    { kind = "dust", cn = "钐", en = "samarium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2069, cell = "gregtech:gt.metaitem.01", cellMeta = 31069 },
    { kind = "dust", cn = "铁", en = "iron", weight = 10, reg = "gregtech:gt.metaitem.01", meta = 2032, cell = "gregtech:gt.metaitem.01", cellMeta = 31032 },
    { kind = "dust", cn = "碲", en = "tellurium", weight = 2, reg = "gregtech:gt.metaitem.01", meta = 2059, cell = "gregtech:gt.metaitem.01", cellMeta = 31059 },
    { kind = "dust", cn = "镉", en = "cadmium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2055, cell = "gregtech:gt.metaitem.01", cellMeta = 31055 },
    { kind = "dust", cn = "奥利哈钢", en = "oriharukon", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2393, cell = "gregtech:gt.metaitem.01", cellMeta = 31393 },
    { kind = "dust", cn = "钾", en = "potassium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2025, cell = "gregtech:gt.metaitem.01", cellMeta = 31025 },
    { kind = "dust", cn = "铯", en = "caesium", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2062, cell = "gregtech:gt.metaitem.01", cellMeta = 31062 },
    { kind = "dust", cn = "钙", en = "calcium", weight = 10, reg = "gregtech:gt.metaitem.01", meta = 2026, cell = "gregtech:gt.metaitem.01", cellMeta = 31026 },
    { kind = "dust", cn = "硫", en = "sulfur", weight = 10, reg = "gregtech:gt.metaitem.01", meta = 2022, cell = "gregtech:gt.metaitem.01", cellMeta = 31022 },
    { kind = "dust", cn = "钼", en = "molybdenum", weight = 6, reg = "gregtech:gt.metaitem.01", meta = 2048, cell = "gregtech:gt.metaitem.01", cellMeta = 31048 },
    { kind = "dust", cn = "镱", en = "ytterbium", weight = 2, reg = "gregtech:gt.metaitem.01", meta = 2077, cell = "gregtech:gt.metaitem.01", cellMeta = 31077 },
    { kind = "gas",  cn = "氦", en = "helium", weight = 10, cell = "gregtech:gt.metaitem.01", cellMeta = 31004 },
    { kind = "gas",  cn = "氢", en = "hydrogen", weight = 10, cell = "gregtech:gt.metaitem.01", cellMeta = 31001 },
    { kind = "gas",  cn = "氯", en = "chlorine", weight = 6, cell = "gregtech:gt.metaitem.01", cellMeta = 31023 },
    { kind = "gas",  cn = "氮", en = "nitrogen", weight = 10, cell = "gregtech:gt.metaitem.01", cellMeta = 31012 },
    { kind = "gas",  cn = "汞", en = "mercury", weight = 6, cell = "gregtech:gt.metaitem.01", cellMeta = 31087 },
    { kind = "gas",  cn = "氘", en = "deuterium", weight = 6, cell = "gregtech:gt.metaitem.01", cellMeta = 31002 },
    { kind = "gas",  cn = "氡", en = "radon", weight = 10, cell = "gregtech:gt.metaitem.01", cellMeta = 31093 },
    { kind = "gas",  cn = "氩", en = "argon", weight = 6, cell = "gregtech:gt.metaitem.01", cellMeta = 31024 },
    { kind = "gas",  cn = "氚", en = "tritium", weight = 6, cell = "gregtech:gt.metaitem.01", cellMeta = 31003 },
    { kind = "gas",  cn = "氟", en = "fluorine", weight = 6, cell = "gregtech:gt.metaitem.01", cellMeta = 31014 },
}
local CI_ITEMS = {
    { cn = "基岩", en = "bedrockium", reg = "gregtech:gt.metaitem.01", meta = 2395, cell = "gregtech:gt.metaitem.01", cellMeta = 31395, plasma = "plasma.bedrockium" , ingot = "gregtech:gt.metaitem.01", ingotMeta = 11395 },
    { cn = "龙", en = "draconium", reg = "gregtech:gt.metaitem.01", meta = 2975, cell = "gregtech:gt.metaitem.01", cellMeta = 31975, plasma = "plasma.draconium" , ingot = "gregtech:gt.metaitem.01", ingotMeta = 11975 },
    { cn = "三钛", en = "tritanium", reg = "gregtech:gt.metaitem.01", meta = 2329, cell = "gregtech:gt.metaitem.01", cellMeta = 31329, plasma = "plasma.tritanium" , ingot = "gregtech:gt.metaitem.01", ingotMeta = 11329 },
    { cn = "海珀珍", en = "hypogen", reg = "miscutils:itemDustHypogen", meta = 0, cell = "miscutils:itemCellPlasmaHypogen", cellMeta = 0, plasma = "plasma.hypogen" , ingot = "miscutils:itemIngotHypogen", ingotMeta = 0 },
    { cn = "龙血", en = "dragonblood", reg = "miscutils:itemDustDragonblood", meta = 0, cell = "miscutils:itemCellPlasmaDragonblood", cellMeta = 0, plasma = "plasma.dragonblood" , ingot = "miscutils:itemIngotDragonblood", ingotMeta = 0 },
    { cn = "灵宝", en = "ichorium", reg = "gregtech:gt.metaitem.01", meta = 2978, cell = "gregtech:gt.metaitem.01", cellMeta = 31978, plasma = "plasma.ichorium" , ingot = "gregtech:gt.metaitem.01", ingotMeta = 11978 },
    { cn = "无尽", en = "infinity", reg = "gregtech:gt.metaitem.01", meta = 2397, cell = "gregtech:gt.metaitem.01", cellMeta = 31397, plasma = "plasma.infinity" , ingot = "gregtech:gt.metaitem.01", ingotMeta = 11397 },
    { cn = "中子", en = "neutronium", reg = "gregtech:gt.metaitem.01", meta = 2129, cell = "gregtech:gt.metaitem.01", cellMeta = 31129, plasma = "plasma.neutronium" , ingot = "gregtech:gt.metaitem.01", ingotMeta = 11129 },
    { cn = "宇宙中子态素", en = "cosmicneutronium", reg = "gregtech:gt.metaitem.01", meta = 2982, cell = "gregtech:gt.metaitem.01", cellMeta = 31982, plasma = "plasma.cosmicneutronium" , ingot = "gregtech:gt.metaitem.01", ingotMeta = 11982 },
    { cn = "彩色玻璃", en = "chromaticglass", reg = "miscutils:itemDustChromaticGlass", meta = 0, cell = "miscutils:itemCellPlasmaChromaticGlass", cellMeta = 0, plasma = "plasma.chromaticglass" , ingot = "miscutils:itemIngotChromaticGlass", ingotMeta = 0 },
    { cn = "𫓧", en = "flerovium", reg = "gregtech:gt.metaitem.01", meta = 2984, cell = "gregtech:gt.metaitem.01", cellMeta = 31984, plasma = "plasma.flerovium_gt5u" , ingot = "gregtech:gt.metaitem.01", ingotMeta = 11984 },
    { cn = "觉醒龙", en = "draconiumawakened", reg = "gregtech:gt.metaitem.01", meta = 2976, cell = "gregtech:gt.metaitem.01", cellMeta = 31976, plasma = "plasma.draconiumawakened" , ingot = "gregtech:gt.metaitem.01", ingotMeta = 11976 },
    { cn = "鲁格诺", en = "rhugnor", reg = "miscutils:itemDustRhugnor", meta = 0, cell = "miscutils:itemCellPlasmaRhugnor", cellMeta = 0, plasma = "plasma.rhugnor" , ingot = "miscutils:itemIngotRhugnor", ingotMeta = 0 },
    { cn = "天体钨", en = "celestialtungsten", reg = "miscutils:itemDustCelestialTungsten", meta = 0, cell = "miscutils:itemCellPlasmaCelestialTungsten", cellMeta = 0, plasma = "plasma.celestialtungsten" , ingot = "miscutils:itemIngotCelestialTungsten", ingotMeta = 0 },
}
local function usedSlots(ifaces)
    local out = {}
    for _, iface in ipairs(ifaces) do
        for slot = 1, lib.patternSlotCount(iface) do
            local ok, p = pcall(iface.getInterfacePattern, slot)
            if ok and p then
                out[#out + 1] = { iface = iface, slot = slot }
            end
        end
    end
    return out
end
local function say(ctx, title, footer)
    if ctx.select then
        ctx.select({ { label = "知道了", value = 1 } }, { title = title, footer = footer })
    else
        ctx.write(title)
    end
end
local function writeOne(s, w, db)
    local nErr = nil
    local iface, slot = s.iface, s.slot
    for i, o in ipairs(w.outs) do
        local ok, err
        if o.rename and db then
            ok, err = pcall(db.set, 1, o.name, o.damage or 0, '{display:{Name:"' .. o.rename .. '"}}')
            if ok then
                ok, err = pcall(iface.setInterfacePatternOutput, slot, i, db.address, 1, o.size or 1)
            end
        elseif o.fluid then
            ok, err = pcall(iface.setInterfacePatternOutput, slot, i, { name = o.name, size = o.size }, "fluid")
        else
            ok, err = pcall(iface.setInterfacePatternOutput, slot, i,
                { name = o.name, size = o.size, damage = o.damage or 0 }, "item")
        end
        if not ok then nErr = tostring(err) end
    end
    for i, e in ipairs(w.ins) do
        local ok, err
        if e.rename and e.renameTo and db then
            ok, err = pcall(db.set, 1, e.name, e.damage or 0, '{display:{Name:"' .. e.renameTo .. '"}}')
            if ok then
                ok, err = pcall(iface.setInterfacePatternInput, slot, i, db.address, 1, e.size)
            end
        elseif e.fluid then
            ok, err = pcall(iface.setInterfacePatternInput, slot, i, { name = e.name, size = e.size }, "fluid")
        else
            local d = { name = e.name, size = e.size, damage = e.damage or 0 }
            if e.tag then d.tag = e.tag end
            ok, err = pcall(iface.setInterfacePatternInput, slot, i, d, "item")
        end
        if not ok then nErr = tostring(err) end
    end
    return nErr
end
local function item(name, size, damage)
    return { name = name, size = size, damage = damage or 0 }
end
local function fluid(name, size)
    return { name = name, size = size, fluid = true }
end
local function plasmaOf(e, size)
    return fluid("plasma." .. e.en, size)
end
local function cellOf(e)
    return item(e.cell, 1, e.cellMeta)
end
local function ingotOf(e)
    return item(e.ingot, 1, e.ingotMeta)
end
local function powderOf(e)
    return item(e.reg, 1, e.meta)
end
local MOLTEN = {
    tritanium = true, hypogen = true, chromaticglass = true,
    dragonblood = true, flerovium = true, infinity = true,
    americium = true, curium = true, rhugnor = true,
}
local function moltenName(en)
    if en == "flerovium" then return "molten.flerovium_gt5u" end
    return "molten." .. en
end
local function genNAC(idx, renameTo)
    local r = RECIPES[idx]
    local ins = {}
    for _, e in ipairs(r.ins) do
        local t = item(e.name, e.size, e.damage)
        t.fluid = e.fluid
        if e.rename then
            t.rename = true
            t.renameTo = renameTo or e.label
        end
        ins[#ins + 1] = t
    end
    local outs = {}
    for _, o in ipairs(r.out) do
        outs[#outs + 1] = item(o.name, o.size, o.damage)
    end
    return { { tag = r.name, outs = outs, ins = ins } }
end
local function genPlasma()
    local list = {}
    for _, e in ipairs(ELEMENTS) do
        if e.kind == "gas" then
            list[#list + 1] = {
                tag = e.cn .. " 气体→等离子",
                outs = { fluid("plasma." .. e.en, 500) },
                ins = { fluid(e.en, 500) },
            }
        elseif MOLTEN[e.en] then
            list[#list + 1] = {
                tag = e.cn .. " 熔融→等离子",
                outs = { plasmaOf(e, 144) },
                ins = { fluid(moltenName(e.en), 144) },
            }
        else
            list[#list + 1] = {
                tag = e.cn .. " 粉→等离子",
                outs = { plasmaOf(e, 144) },
                ins = { powderOf(e) },
            }
        end
    end
    for _, e in ipairs(CI_ITEMS) do
        if MOLTEN[e.en] then
            list[#list + 1] = {
                tag = e.cn .. " 熔融→等离子（磁物质）",
                outs = { fluid(e.plasma, 144) },
                ins = { fluid(moltenName(e.en), 144) },
            }
        else
            list[#list + 1] = {
                tag = e.cn .. " 粉→等离子（磁物质）",
                outs = { fluid(e.plasma, 144) },
                ins = { powderOf(e) },
            }
        end
    end
    return list
end
local function genQuark(which)
    local list = {}
    if which == "fapei" then
        for _, e in ipairs(ELEMENTS) do
            if e.kind == "gas" then
                list[#list + 1] = {
                    tag = e.cn .. " 气体→单元",
                    outs = { cellOf(e) },
                    ins = { fluid(e.en, 1), plasmaOf(e, 1000) },
                }
            else
                list[#list + 1] = {
                    tag = e.cn .. " 粉→单元",
                    outs = { cellOf(e) },
                    ins = { powderOf(e), plasmaOf(e, 1296) },
                }
            end
        end
    elseif which == "sum" then
        local ins = {}
        for _, e in ipairs(ELEMENTS) do
            ins[#ins + 1] = item(e.cell, 2000000000, e.cellMeta)
        end
        list[1] = {
            tag = "夸克汇总下单",
            outs = { item("minecraft:iron_sword", 1) },
            ins = ins,
        }
    elseif which == "refill" then
        local ins = {}
        for _, e in ipairs(ELEMENTS) do
            local per = (e.kind == "gas") and 1000 or 1296
            ins[#ins + 1] = fluid("plasma." .. e.en, e.weight * per)
        end
        list[1] = {
            tag = "夸克等离子补货",
            outs = { { name = "minecraft:fish", size = 1, damage = 0, rename = "夸克等离子补货" } },
            ins = ins,
        }
    end
    return list
end
local function genCI(which)
    local list = {}
    if which == "fapei" then
        for _, e in ipairs(CI_ITEMS) do
            list[#list + 1] = {
                tag = e.cn .. " 发配",
                outs = { cellOf(e) },
                ins = { powderOf(e), fluid(e.plasma, 144), fluid("spatialfluid", 1) },
            }
        end
        list[#list + 1] = {
            tag = "富快子+空间流体",
            outs = { item("minecraft:iron_sword", 1) },
            ins = { fluid("temporalfluid", 1), fluid("spatialfluid", 1) },
        }
    elseif which == "powder" then
        for _, e in ipairs(CI_ITEMS) do
            list[#list + 1] = {
                tag = e.cn .. " 粉→锭",
                outs = { ingotOf(e) },
                ins = { powderOf(e) },
            }
        end
    elseif which == "sum" then
        local ins1 = {}
        for _, e in ipairs(CI_ITEMS) do
            ins1[#ins1 + 1] = ingotOf(e)
        end
        list[#list + 1] = {
            tag = "汇总·锭→金剑",
            outs = { item("minecraft:golden_sword", 1) },
            ins = ins1,
        }
        local ins2 = {}
        for _, e in ipairs(CI_ITEMS) do
            ins2[#ins2 + 1] = cellOf(e)
        end
        ins2[#ins2 + 1] = item("minecraft:golden_sword", 1)
        ins2[#ins2 + 1] = item("minecraft:iron_sword", 1)
        list[#list + 1] = {
            tag = "汇总·单元+剑→钻石剑",
            outs = { item("minecraft:diamond_sword", 1) },
            ins = ins2,
        }
    elseif which == "refill" then
        local ins = {}
        for _, e in ipairs(CI_ITEMS) do
            ins[#ins + 1] = fluid(e.plasma, 1296)
        end
        list[1] = {
            tag = "磁物质补货",
            outs = { { name = "minecraft:fish", size = 1, damage = 0, rename = "磁物质等离子补货" } },
            ins = ins,
        }
    end
    return list
end
local function runList(ctx, ifaces, list, db, channels)
    local total = #list
    local idx = 1
    local nOk, nErr = 0, 0
    ctx.clear()
    ctx.write(string.format("共 %d 个样板，分批写入", total))
    ctx.write("每批写满当前所有占位样板后暂停，换好再继续")
    -- 通道样板状态与引用提示(替换发生在生成阶段)
    if channels and (channels.red or channels.blue) then
        local parts = {}
        if channels.red then
            parts[#parts + 1] = "红板@槽" .. channels.red.slot .. (channels.red.tagOk and "" or "(缺tag,未引用)")
        end
        if channels.blue then
            parts[#parts + 1] = "蓝板@槽" .. channels.blue.slot .. (channels.blue.tagOk and "" or "(缺tag,未引用)")
        end
        ctx.write("  通道样板: " .. table.concat(parts, "  "))
    end
    local nRef = 0
    for _, w in ipairs(list) do
        for _, e in ipairs(w.ins) do
            if e.channelRef then
                nRef = nRef + 1
                ctx.write(string.format("  %s → 引用通道样板(槽%d) x%d", w.tag, e.chSlot, e.chCount))
            end
        end
    end
    if nRef > 0 then ctx.write("") end
    -- 通道样板槽不可被覆写
    local skipSlot = {}
    if channels then
        if channels.red then skipSlot[channels.red.slot] = true end
        if channels.blue then skipSlot[channels.blue.slot] = true end
    end
    while idx <= total do
        local slots = usedSlots(ifaces)
        do
            local filtered = {}
            for _, s in ipairs(slots) do
                if not skipSlot[s.slot] then filtered[#filtered + 1] = s end
            end
            slots = filtered
        end
        if #slots == 0 then
            if not ctx.select then
                ctx.write("没有可写的样板槽")
                return false
            end
            local go = ctx.select({
                { label = "已放好，继续", value = true },
                { label = "退出", value = false },
            }, {
                title = string.format("接口里没有占位样板（还剩 %d 个没写）", total - idx + 1),
                footer = "把占位样板放进接口，再选「已放好，继续」",
            })
            if not go then return true end
        else
            local batch = math.min(#slots, total - idx + 1)
            for j = 1, batch do
                local w = list[idx + j - 1]
                local err = writeOne(slots[j], w, db)
                if err then
                    nErr = nErr + 1
                    ctx.write(string.format("  [%d] %s 失败: %s", idx + j - 1, w.tag, err))
                else
                    nOk = nOk + 1
                end
                os.sleep(0)
            end
            idx = idx + batch
            if idx <= total then
                local go = true
                if ctx.select then
                    go = ctx.select({
                        { label = "已换好，继续", value = true },
                        { label = "退出", value = false },
                    }, {
                        title = string.format("已写 %d/%d，还剩 %d 个", idx - 1, total, total - idx + 1),
                        footer = "把这批样板拿走、放新的占位样板，再选「已换好，继续」",
                    })
                elseif ctx.pause then
                    ctx.pause("把这批样板拿走、放新的占位样板，按任意键继续")
                end
                if not go then return true end
            end
        end
    end
    ctx.write("")
    ctx.write(string.format("完成：成功 %d，失败 %d", nOk, nErr))
    if ctx.pause then ctx.pause("") end
    return nErr == 0
end
local function menu(ctx, items, title)
    return ctx.select(items, { title = title })
end
function M.run(ctx, args)
    local ifaces = findIfaces()
    if #ifaces == 0 then
        say(ctx, "找不到ME接口", "检查适配器是否紧贴 ME 接口")
        return false
    end
    local slots = usedSlots(ifaces)
    if #slots == 0 then
        say(ctx, "接口里没有样板", "先往接口里塞占位样板，工具只覆盖已有样板的槽")
        return false
    end
    local pick = menu(ctx, {
        { label = "皮米电路", desc = "NAC · 31 项输入", value = "nac:1" },
        { label = "量子电路", desc = "NAC · 36 项输入", value = "nac:2" },
        { label = "神锻等离子样板", desc = "94 种 → 等离子", value = "plasma" },
        { label = "夸克 · 发配样板", desc = "粉+1296 / 气体+1000 → 单元", value = "quark:fapei" },
        { label = "夸克 · 汇总下单", desc = "80 单元 ×2e9 → 铁剑", value = "quark:sum" },
        { label = "夸克 · 等离子补货", desc = "80 等离子×权重 → 生鳕鱼", value = "quark:refill" },
        { label = "磁物质 · 发配样板", desc = "14 种材料 + 富快子捆绑", value = "ci:fapei" },
        { label = "磁物质 · 纯粉发配", desc = "14 种粉 → 对应锭", value = "ci:powder" },
        { label = "磁物质 · 汇总下单", desc = "2 个：锭→金剑 / 单元→钻石剑", value = "ci:sum" },
        { label = "磁物质 · 等离子补货", desc = "14 等离子 → 生鳕鱼", value = "ci:refill" },
    }, string.format("样板生成：%d 个接口 / %d 个可用槽", #ifaces, #slots))
    if not pick then return true end
    local group, key = pick:match("^([^:]+):(.+)$")
    -- 通道样板检测(一次);红/蓝板存在时 NAC 电路样板的对应项组自动替换为通道引用
    local channels = findChannelPatterns(ifaces)
    local list
    if group == "nac" then
        local idx = tonumber(key)
        -- 先试探替换: 改名项被通道引用完全覆盖时,跳过改名询问
        local trial = applyChannelReplacement(genNAC(idx, nil), channels)
        local hasRenameLeft = false
        for _, w in ipairs(trial) do
            for _, e in ipairs(w.ins) do
                if e.rename then hasRenameLeft = true end
            end
        end
        local renameTo = nil
        if hasRenameLeft then
            ctx.clear()
            ctx.write("重命名物品")
            ctx.write("")
            ctx.write("这个样板里有几个物品需要统一改名，输入名字就行。")
            ctx.write("回车确定，留空则用原名")
            ctx.write("")
            renameTo = ctx.ask("名字> ", "")
            if renameTo == "" then renameTo = nil end
            ctx.clear()
        end
        list = applyChannelReplacement(genNAC(idx, renameTo), channels)
    elseif pick == "plasma" then
        list = applyChannelReplacement(genPlasma(), channels)
    elseif group == "quark" then
        list = applyChannelReplacement(genQuark(key), channels)
    elseif group == "ci" then
        list = applyChannelReplacement(genCI(key), channels)
    end
    if not list or #list == 0 then return true end
    applyCuttingFluidChoice(list, ctx)
    local db = findDb()
    if (group == "quark" or group == "ci") and not db then
        local needRename = false
        for _, w in ipairs(list) do
            for _, o in ipairs(w.outs) do
                if o.rename then needRename = true end
            end
            for _, e in ipairs(w.ins) do
                if e.rename then needRename = true end
            end
        end
        if needRename then
            say(ctx, "需在适配器中放入数据库升级", "要写重命名物品，需在适配器中放入数据库升级")
            return false
        end
    end
    return runList(ctx, ifaces, list, db, channels)
end
return M
