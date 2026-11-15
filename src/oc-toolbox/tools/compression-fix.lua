
local component = require("component")
local lib = require("ae2_iface")
local findIface, patternSlotCount = lib.findIface, lib.patternSlotCount
local M = {
    id = "compression-fix",
    name = "压模改固化",
    group = "AE2 样板",
    order = 50,
    desc = "按模具形状把输入换成对应熔融流体",
}
local SHAPE_WORDS = {
    "Turbine Blade", "Drill Tip", "Drill Head", "Pipe", "Gear", "Rod", "Rotor",
    "Plate", "Ring", "Screw", "Bolt", "Round", "Ingot", "Nugget",
    "Block", "Casing", "Stick",
}
local function matchShape(label)
    local lb = label
    local function has(w)
        return lb:find(w, 1, true) ~= nil
    end
    if has("Turbine Blade") then return { key = "Turbine Blade", l = 864, cn = "涡轮扇叶" } end
    if has("Drill Tip") then return { key = "Drill Tip", l = 576, cn = "钻头" } end
    if has("Drill Head") then return { key = "Drill Head", l = 576, cn = "钻头" } end
    if has("Pipe") then
        if has("Tiny") then return { key = "Tiny Pipe", l = 72, cn = "微型管道" } end
        if has("Small") then return { key = "Small Pipe", l = 144, cn = "小型管道" } end
        if has("Huge") then return { key = "Huge Pipe", l = 1728, cn = "巨型管道" } end
        if has("Large") then return { key = "Large Pipe", l = 864, cn = "大型管道" } end
        if has("Medium") then return { key = "Medium Pipe", l = 432, cn = "管道" } end
        return { key = "Pipe", l = 432, cn = "管道" }
    end
    if has("Gear") then
        if has("Small") then return { key = "Small Gear", l = 144, cn = "小型齿轮" } end
        return { key = "Gear", l = 576, cn = "齿轮" }
    end
    if has("Rod") then
        if has("Long") then return { key = "Long Rod", l = 144, cn = "长杆" } end
        return { key = "Rod", l = 72, cn = "杆" }
    end
    if has("Rotor") then return { key = "Rotor", l = 612, cn = "转子" } end
    if has("Plate") then return { key = "Plate", l = 144, cn = "板" } end
    if has("Ring") then return { key = "Ring", l = 36, cn = "环" } end
    if has("Screw") then return { key = "Screw", l = 18, cn = "螺丝" } end
    if has("Bolt") then return { key = "Bolt", l = 18, cn = "螺栓" } end
    if has("Round") then return { key = "Round", l = 16, cn = "滚珠" } end
    if has("Ingot") then return { key = "Ingot", l = 144, cn = "锭" } end
    if has("Nugget") then return { key = "Nugget", l = 16, cn = "粒" } end
    if has("Block") then return { key = "Block", l = 1296, cn = "块" } end
    if has("Casing") then return { key = "Casing", l = 72, cn = "外壳" } end
    if has("Stick") then return { key = "Stick", l = 72, cn = "杆" } end
    return nil
end
local function materialOf(label)
    local m = label
    m = m:gsub("^Tiny%s+", ""):gsub("^Small%s+", ""):gsub("^Large%s+", "")
    m = m:gsub("^Huge%s+", ""):gsub("^Medium%s+", ""):gsub("^Long%s+", "")
    m = m:gsub("^Hot%s+", "")
    for _, w in ipairs(SHAPE_WORDS) do
        m = m:gsub("%s*" .. w .. "$", "")
    end
    m = m:gsub("^Block%s+of%s+", "")
    m = m:gsub("^Block%s+", "")
    m = m:gsub("^of%s+", "")
    m = m:gsub("%s*Fluid$", "")
    m = m:gsub("^%s+", ""):gsub("%s+$", "")
    return m
end
local ALIASES = {
    ["plutonium239"] = "molten.plutonium",
    ["rawsilicon"] = "molten.silicon",
    ["uranium238"] = "molten.uranium",
    ["awakeneddraconium"] = "molten.draconiumawakened",
    ["endium"] = "molten.heeendium",
    ["deepdarkiron"] = "molten.darkiron",
    ["fluxedelectrum"] = "molten.electrumflux",
    ["hslasteel"] = "molten.hsla",
    ["enrichednaquadah"] = "molten.naquadahenriched",
    ["fluxedobsidian"] = "molten.obsidianflux",
    ["voidmetal"] = "molten.void",
    ["polyethylene"] = "molten.plastic",
    ["siliconerubber"] = "molten.silicone",
    ["purifiedtengam"] = "molten.tengampurified",
    ["attunedtengam"] = "molten.tengamattuned",
    ["siliconsolargradepolysi"] = "molten.siliconsolargrade",
    ["obzinite"] = "molten.alumite",
    ["fiberreinforcedepoxyresin"] = "molten.epoxidfiberreinforced",
    ["blackgranite"] = "molten.graniteblack",
    ["magneticiron"] = "molten.ironmagnetic",
    ["magneticneodymium"] = "molten.neodymiummagnetic",
    ["magneticsamarium"] = "molten.samariummagnetic",
    ["magneticsteel"] = "molten.steelmagnetic",
    ["redgranite"] = "molten.granitered",
    ["shadowmetal"] = "molten.shadow",
    ["claycompound"] = "molten.crudesteel",
    ["superconductorbasemv"] = "molten.pentacadmiummagnesiumhexaoxid",
    ["superconductorbasehv"] = "molten.titaniumonabariumdecacoppereikosaoxid",
    ["superconductorbaseev"] = "molten.uraniumtriplatinid",
    ["superconductorbaseiv"] = "molten.vanadiumtriindinid",
    ["superconductorbaseluv"] = "molten.tetraindiumditindibariumtitaniumheptacoppertetrakaidekaoxid",
    ["superconductorbasezpm"] = "molten.tetranaquadahdiindiumhexaplatiumosminid",
    ["superconductorbaseuv"] = "molten.longasssuperconductornameforuvwire",
    ["superconductorbaseuhv"] = "molten.longasssuperconductornameforuhvwire",
    ["superconductorbaseuev"] = "molten.superconductoruevbase",
    ["superconductorbaseuiv"] = "molten.superconductoruivbase",
    ["superconductorbaseumv"] = "molten.superconductorumvbase",
    ["radoxpolymer"] = "molten.radoxpoly",
}
local function fluidCandidates(mat)
    local out = {}
    local key = mat:lower():gsub("[^%w]", "")
    if ALIASES[key] then
        out[#out + 1] = ALIASES[key]
    end
    local a = mat:lower():gsub("%s+", "_")
    local b = mat:lower():gsub("%s+", "")
    out[#out + 1] = "molten." .. a
    if b ~= a then out[#out + 1] = "molten." .. b end
    return out
end
function M.run(ctx, args)
    local iface = findIface()
    if not iface then
        if ctx.select then
            ctx.select({ { label = "知道了", value = 1 } }, {
                title = "找不到ME接口", footer = "检查适配器是否紧贴方块",
            })
        else
            ctx.write("找不到ME接口")
        end
        return false
    end
    ctx.clear()
    ctx.write("压模改固化：扫描全部样板")
    ctx.write(string.rep("-", 56))
    local nDone, nSkip, nFail = 0, 0, 0
    for slot = 1, patternSlotCount(iface) do
        local okP, p = pcall(iface.getInterfacePattern, slot)
        if okP and p and p.outputs then
            local best = nil
            for _, e in pairs(p.outputs) do
                local lb = tostring(e.label or "")
                if lb ~= "" and not tostring(e.name or ""):lower():find("molten") then
                    local s = matchShape(lb)
                    if s then
                        best = { e = e, shape = s, label = lb }
                        break
                    end
                end
            end
            if best then
                local mat = materialOf(best.label)
                local need = (tonumber(best.e.size) or 1) * best.shape.l
                local targetIdx, targetLabel, alreadyFluid = nil, nil, false
                if p.inputs then
                    for idx, e in pairs(p.inputs) do
                        local inLabel = tostring(e.label or "")
                        local inName = tostring(e.name or ""):lower()
                        if inLabel:lower():find(mat:lower(), 1, true) then
                            if inName:find("molten") or inName:find("fluid") then
                                alreadyFluid = true
                                targetLabel = inLabel
                            else
                                targetIdx, targetLabel = idx, inLabel
                            end
                            break
                        end
                    end
                end
                if alreadyFluid then
                    nSkip = nSkip + 1
                elseif not targetIdx then
                    nSkip = nSkip + 1
                    ctx.write(string.format("槽%d %s：输入里没有含「%s」的项",
                        slot, best.shape.cn, mat))
                else
                    local done = false
                    for _, fname in ipairs(fluidCandidates(mat)) do
                        local okc = pcall(function()
                            return iface.setInterfacePatternInput(slot, targetIdx,
                                { name = fname, size = need }, "fluid")
                        end)
                        if okc then
                            done = true
                            break
                        end
                    end
                    if done then
                        nDone = nDone + 1
                        ctx.write(string.format("槽%d %s ×%s → %s ×%d",
                            slot, best.shape.cn, tostring(best.e.size),
                            fluidCandidates(mat)[1], need))
                    else
                        nFail = nFail + 1
                        ctx.write(string.format("槽%d %s：流体名 %s 不存在",
                            slot, best.shape.cn, fluidCandidates(mat)[1]))
                    end
                end
            end
        end
        os.sleep(0)
    end
    ctx.write(string.rep("-", 56))
    ctx.write(string.format("完成：改了 %d 个，跳过 %d 个，失败 %d 个", nDone, nSkip, nFail))
    if ctx.select then
        ctx.select({ { label = "好了", value = 1 } }, {
            title = string.format("压模改固化：改 %d / 跳过 %d / 失败 %d", nDone, nSkip, nFail),
            footer = "输入已经是流体的样班会自动跳过",
        })
    end
    return nFail == 0
end
return M
