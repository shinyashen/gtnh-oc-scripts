local os = require("os")
local component = require("component")

-- ====== 配置 ======
local sleepTime = 30 --检测间隔（秒）
local pumpBatch = nil  --所有钻机批处理数，nil为不自动设置
local allowRandomMine = true --库存达标后是否继续随机挖矿
local printMonitorDetail = false --是否打印监控目标明细
local version = "v2.3-290适配r14钻机多线程版"

-- ====== 流体/物品读取组件自动探测（290：用invoke直调，绕开proxy字段缺陷） ======
local fluidAddr, fluidName = nil, nil

local function methodsHas(addr, method)
    if type(component.methods) ~= "function" then return nil end
    local ok, mlist = pcall(component.methods, addr)
    if not ok or type(mlist) ~= "table" then return nil end
    return mlist[method] ~= nil
end

local function bindFluid(addr, name)
    fluidAddr, fluidName = addr, name
    print("流体读取组件: " .. name .. "  地址: " .. addr)
    local ok, list = pcall(component.invoke, addr, "getFluidsInNetwork")
    print(ok and type(list) == "table" and ("自检通过：可见流体 " .. #list .. " 种") or ("警告：getFluidsInNetwork调用失败：" .. tostring(list)))
    return true
end

local function detectFluidReader(verbose)
    -- AE2的ME接口/控制器带全套物品+流体方法；AE2FC流体接口(fluid_interface)读不了库存
    for _, name in ipairs({ "me_interface", "me_controller", "fluid_interface", "iohub" }) do
        local addr = component.list(name)()
        if addr and (name == "me_interface" or name == "me_controller" or methodsHas(addr, "getFluidsInNetwork")) then
            return bindFluid(addr, name)
        end
    end
    if verbose then print("按名称未找到，扫描OC网络全部组件...") end
    for addr, name in component.list() do
        if methodsHas(addr, "getFluidsInNetwork") or methodsHas(addr, "getFluidInNetwork") then
            return bindFluid(addr, name)
        end
    end
    if verbose then
        print("错误：未找到能读流体的组件！请把AE2的ME接口或ME控制器紧贴OC线缆/适配器放置并接入AE网络")
        local ok = pcall(function()
            local f = io.open("oc_components.txt", "w")
            if not f then return end
            local found = {}
            for a, n in component.list() do found[n] = (found[n] or 0) + 1 end
            for n, c in pairs(found) do f:write(string.format("%s x%d\n", n, c)) end
            f:close()
        end)
        if ok then print("组件清单已存 oc_components.txt（cat 查看），10秒后继续运行") end
        os.sleep(10)
    end
    return false
end

-- ====== 流体库存（每周期一次getFluidsInNetwork建缓存，失败退化为按名查询） ======
local fluidCache = nil
local function refreshFluidCache()
    if not fluidAddr then fluidCache = {} return end
    local ok, fluids = pcall(component.invoke, fluidAddr, "getFluidsInNetwork")
    if ok and type(fluids) == "table" then
        fluidCache = {}
        for _, f in ipairs(fluids) do
            if f and f.name then fluidCache[f.name] = (fluidCache[f.name] or 0) + (f.amount or 0) end
        end
    else
        fluidCache = nil
    end
end

local function getFluidAmount(name)
    if fluidCache then return fluidCache[name] or 0 end
    if fluidAddr then
        local ok, detail = pcall(component.invoke, fluidAddr, "getFluidInNetwork", name)
        if ok and type(detail) == "table" and detail.amount then return math.max(0, detail.amount or 0) end
    end
    return 0
end

-- ====== 钻机/矿机发现（gt_machine）与参数写入（290新API：setParameter键名,值） ======
-- 泵机键: recipeN.planetType / recipeN.gasType（N=0..线程数-1，T2/T3各4线程，目标流体写入全部线程）/ batch；矿机键: distance等（识别用小写模糊匹配）
local pumps, miners = {}, {}
for address, name in component.list("gt_machine") do
    local gtm = component.proxy(address)
    if gtm.getName():match("projectmodulepump(.+)$") then table.insert(pumps, gtm) end
    if gtm.getName():match("projectmoduleminer(.+)$") then table.insert(miners, gtm) end
end

local levelMaintainers = {}
for address, name in component.list("level_maintainer") do
    table.insert(levelMaintainers, component.proxy(address))
end

local pumpTT, minerTT = {}, {}     --泵机/矿机的参数写入地址
local pumpKeys, minerKeys = {}, {} --地址 -> 已解析的键名映射

local function getParams(addr)
    local ok, params = pcall(component.invoke, addr, "getParameters")
    if ok and type(params) == "table" then return params end
    return nil
end

local function resolveKeys(addr)
    local params = getParams(addr)
    if not params then return nil end
    local map = { threads = {} }
    for k, v in pairs(params) do
        local lk = tostring(k):lower()
        --多线程钻机（T2/T3 各4线程）：recipeN.planetType / recipeN.gasType，按共同前缀 "recipeN." 归组，全部线程都要写入
        local p = lk:find("planet", 1, true)
        if p then
            local prefix = tostring(k):sub(1, p - 1)
            map.threads[prefix] = map.threads[prefix] or {}
            map.threads[prefix].planet = k
        end
        local g = lk:find("gas", 1, true)
        if g then
            local prefix = tostring(k):sub(1, g - 1)
            map.threads[prefix] = map.threads[prefix] or {}
            map.threads[prefix].gas = k
        end
        if not map.batch and lk == "batch" then map.batch = k end
        if not map.distance and lk == "distance" then map.distance = k end
        if not map.overdrive and type(v) == "number" and lk:find("overdr", 1, true) then map.overdrive = k end
    end
    if not map.overdrive then --超频键按值特征锁定（1~4之间唯一小数；部分版本无此键则跳过）
        for k, v in pairs(params) do
            local lk = tostring(k):lower()
            if not map.overdrive and type(v) == "number" and v > 1 and v < 4 and v % 1 > 0.001 and lk ~= "distance" then
                map.overdrive = k
            end
        end
    end
    return map
end

local function setParam(addr, key, value)
    local ok, err = pcall(component.invoke, addr, "setParameter", key, value)
    if not ok then print("  参数写入失败 [" .. key .. "=" .. tostring(value) .. "]：" .. tostring(err)) end
    return ok
end

local function discoverMachines()
    pumpTT, minerTT, pumpKeys, minerKeys = {}, {}, {}, {}
    for _, m in ipairs(pumps) do table.insert(pumpTT, m.address) end
    for _, m in ipairs(miners) do table.insert(minerTT, m.address) end
    for _, addr in ipairs(pumpTT) do
        pumpKeys[addr] = resolveKeys(addr)
        local map = pumpKeys[addr]
        local threadCount = 0
        if map then
            for _, t in pairs(map.threads) do threadCount = threadCount + 1 end
        end
        if threadCount == 0 then
            print("警告：钻机 " .. addr .. " 未识别出行星/气体键名")
        else
            print("钻机键名：共 " .. threadCount .. " 个线程")
            for prefix, t in pairs(map.threads) do
                if t.planet and t.gas then
                    print("  [" .. prefix .. "] 行星=[" .. t.planet .. "] 气体=[" .. t.gas .. "]")
                else
                    print("  警告：[" .. tostring(prefix) .. "] 键名不完整 行星=" .. tostring(t.planet) .. " 气体=" .. tostring(t.gas))
                end
            end
        end
    end
    for _, addr in ipairs(minerTT) do
        minerKeys[addr] = resolveKeys(addr)
        local map = minerKeys[addr]
        if map and map.distance then
            print("矿机键名：距离=[" .. map.distance .. "]" .. (map.overdrive and (" 超频=[" .. map.overdrive .. "]") or "（无超频键，跳过）"))
        else
            print("警告：矿机 " .. addr .. " 未识别出距离键名")
        end
    end
end

local function setPumpParams(planet, gas)
    for _, addr in ipairs(pumpTT) do
        local map = pumpKeys[addr] or resolveKeys(addr)
        pumpKeys[addr] = map
        if map then
            local threadCount = 0
            for _, t in pairs(map.threads) do
                if t.planet and t.gas then
                    setParam(addr, t.planet, planet)
                    setParam(addr, t.gas, gas)
                    threadCount = threadCount + 1
                end
            end
            local params = getParams(addr)
            if params then
                for k, v in pairs(params) do
                    local lk = tostring(k):lower()
                    if lk:find("planet", 1, true) or lk:find("gas", 1, true) then
                        print("  读回 [" .. k .. "] = " .. tostring(v))
                    end
                end
            end
            print("  已写入 " .. threadCount .. " 个线程的行星/气体")
        end
    end
end

local function setMinerParams(dist, oc)
    for _, addr in ipairs(minerTT) do
        local map = minerKeys[addr] or resolveKeys(addr)
        minerKeys[addr] = map
        if map and map.distance then
            setParam(addr, map.distance, dist)
            if map.overdrive then setParam(addr, map.overdrive, oc) end
            local params = getParams(addr)
            if params then
                for k, v in pairs(params) do
                    if tostring(k):lower() == "distance" then
                        print("  读回 [" .. k .. "] = " .. tostring(v))
                    end
                end
            end
        end
    end
end

-- ====== ME接口辅助（物品读取/无人机配方，invoke直调） ======
local db = component.database

local function findMEWith(method)
    for _, name in ipairs({ "me_interface", "me_controller" }) do
        local addr = component.list(name)()
        if addr and methodsHas(addr, method) ~= false then return addr end
    end
    if fluidAddr and methodsHas(fluidAddr, method) then return fluidAddr end
    return nil
end

function GetUtf8Len(str) --获取包含中文的字符串的显示宽度
    local len = 0
    local currentIndex = 1
    while currentIndex <= #str do
        local char = string.byte(str, currentIndex)
        currentIndex = currentIndex + (char > 240 and 4 or char > 225 and 3 or char > 192 and 2 or 1)
        len = len + (char > 192 and 2 or 1)
    end
    return len
end

local function formatNumber(n)
    if n >= 1e15 then return string.format("%.2fP", n / 1e15)
    elseif n >= 1e9 then return string.format("%.2fG", n / 1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.2fK", n / 1e3)
    else return tostring(n) end
end

local function formatParas(target)
    if target.isFluid then
        return string.format("行星:%d 气体:%d", (target.paras // 1000) % 100, target.paras % 1000)
    end
    return string.format("无人机:%d 距离:%d 超频:%.4f",
        target.paras // 100000000, (target.paras // 100000) % 1000, (target.paras % 100000) / 10000)
end

local function getMonitoringTargets()
    local targets = { items = {}, fluids = {} }
    local existingTargets = {}
    for _, maintainer in ipairs(levelMaintainers) do
        for slot = 1, 5 do
            local success, slotData = pcall(function() return maintainer.getSlot(slot) end)
            if success and slotData and slotData.isEnable then
                local target = {
                    id = slotData.name,
                    displayName = slotData.label or slotData.name,
                    buffer = slotData.quantity or 0,
                    paras = slotData.batch or 0,
                    isFluid = slotData.isFluid or false
                }
                if target.isFluid then
                    target.id = slotData.fluid and slotData.fluid.name or slotData.name
                else
                    target.damage = slotData.damage or 0
                    local nameFromID, damageFromID = target.id:match("^(.+):(%d+)$")
                    if nameFromID and damageFromID then
                        target.name, target.damage = nameFromID, tonumber(damageFromID)
                    else
                        target.name = target.id
                    end
                    if slotData.damage and slotData.damage > 0 then target.damage = slotData.damage end
                end
                local uniqueKey = target.id .. (target.damage or 0) .. tostring(target.isFluid)
                if not existingTargets[uniqueKey] then
                    existingTargets[uniqueKey] = true
                    if target.isFluid then table.insert(targets.fluids, target)
                    else table.insert(targets.items, target) end
                    if printMonitorDetail then
                        io.write(target.displayName, string.rep(" ", 20 - GetUtf8Len(target.displayName)))
                        io.write(string.format("%-12s", formatNumber(target.buffer)))
                        print(formatParas(target))
                    end
                end
            elseif not success then
                print(string.format("[警告] 获取缓存器槽位 %d 数据失败: %s", slot, tostring(slotData)))
            end
        end
    end
    return targets
end

local function printRatio(title, targets, stockRatio)
    io.write(title .. "名称：    ")
    local colWidth, perRow = 36, 4
    for i, t in ipairs(targets) do
        io.write(t.displayName, string.rep(" ", colWidth - GetUtf8Len(t.displayName)))
        if i % perRow == 0 and i < #targets then
            io.write("\n" .. title .. "比例：    ")
            for j = i - perRow + 1, i do
                local r = stockRatio[j]
                if r * 100 > 100 then r = 1 end
                io.write(string.format("%-" .. colWidth .. "s", string.format("%.2f%%", r * 100)))
            end
            io.write("\n" .. title .. "名称：    ")
        end
    end
    io.write("\n" .. title .. "比例：    ")
    for j = #targets - ((#targets - 1) % perRow), #targets do
        local r = stockRatio[j]
        if r * 100 > 100 then r = 1 end
        io.write(string.format("%-" .. colWidth .. "s", string.format("%.2f%%", r * 100)))
    end
    print()
end

local function getFluidRatio(targetFluids)
    if #targetFluids == 0 then return {} end
    local stockRatio = {}
    for _, tfluid in ipairs(targetFluids) do
        local buffer = tfluid.buffer ~= 0 and tfluid.buffer or 1
        stockRatio[_] = getFluidAmount(tfluid.id) / buffer
        if stockRatio[_] > 1 and tfluid.paras > 100000 then stockRatio[_] = math.huge end
    end
    printRatio("流体", targetFluids, stockRatio)
    return stockRatio
end

local function getItemRatio(targetItems)
    local stockRatio = {}
    local itemAddr = findMEWith("getItemsInNetwork")
    if not itemAddr then
        print("警告：未找到可读物品的ME组件")
        return stockRatio
    end
    for _, item in ipairs(targetItems) do
        local filter = { name = item.name }
        if item.damage and item.damage > 0 then filter.damage = item.damage end
        local success, items = pcall(component.invoke, itemAddr, "getItemsInNetwork", filter)
        if not success then
            print("寻找:", item.name, item.damage, item.displayName, "时出错，退出程序")
            os.exit(114514)
        end
        local currentAmount = 0
        for __, itemStack in ipairs(items or {}) do
            if itemStack and itemStack.name == item.name and (itemStack.damage or 0) == item.damage then
                currentAmount = currentAmount + (itemStack.size or 0)
            end
        end
        local buffer = item.buffer ~= 0 and item.buffer or 1
        table.insert(stockRatio, currentAmount / buffer)
        if stockRatio[_] > 1 and item.paras > 100000 then stockRatio[_] = math.huge end
    end
    printRatio("物品", targetItems, stockRatio)
    return stockRatio
end

local function minIndex(t)
    if #t == 0 then return nil end
    local min_idx, min_val = 1, t[1]
    for i = 2, #t do
        if t[i] < min_val then min_val, min_idx = t[i], i end
    end
    return min_idx, min_val
end

local function stopMachine(machines)
    for _, machine in ipairs(machines) do machine.setWorkAllowed(false) end
    local gtmWork, stoptime = true, 0
    while gtmWork do
        gtmWork = false
        for _, machine in ipairs(machines) do
            if machine.isMachineActive() then gtmWork = true break end
        end
        os.sleep(1)
        stoptime = stoptime + 1
        if stoptime > 129 then print("停机超时") end
    end
end

local function changeDrone(droneLevel)
    local meAddr = findMEWith("setInterfaceConfiguration")
    if not meAddr then
        print("警告：未找到ME接口，无法修改无人机配方")
        return
    end
    print("正在修改无人机配方，等级：", droneLevel)
    local droneSlot = 2 * (droneLevel - 1) + 1
    if db.get(droneSlot) and db.get(droneSlot + 1) then
        pcall(component.invoke, meAddr, "setInterfaceConfiguration", 1, db.address, droneSlot, 64)
        pcall(component.invoke, meAddr, "setInterfaceConfiguration", 2, db.address, droneSlot + 1, 64)
    else
        print("无人机等级设置失败，数据库槽位读取异常")
    end
end

-- ====== 启动 ======
detectFluidReader(true)
discoverMachines()

print("等待矿机完成本周期运行")
if pumpBatch then
    stopMachine(pumps)
    for _, addr in ipairs(pumpTT) do
        local map = pumpKeys[addr]
        if map and map.batch then setParam(addr, map.batch, pumpBatch) end
    end
end

local preFluidPara, preItemPara = 0, 0
while true do
    os.execute("cls")
    print("太空电梯智能控制系统 ", version)
    if fluidAddr then
        print("流体读取组件: " .. fluidName)
    else
        detectFluidReader(false)
        if fluidAddr then
            print("流体读取组件: " .. fluidName .. "（重新绑定成功）")
        else
            print("警告：流体读取组件未绑定！组件清单见 oc_components.txt")
        end
    end

    print("==================================\n正在读取监控目标")
    local targets = getMonitoringTargets()
    print("==================================\n正在读取当前库存")
    local fluidIdx, fluidMin = nil, nil
    if fluidAddr then
        refreshFluidCache()
        fluidIdx, fluidMin = minIndex(getFluidRatio(targets.fluids))
    elseif #targets.fluids > 0 then
        print(string.format("流体监控不可用（组件未绑定），已跳过 %d 个流体目标", #targets.fluids))
    end
    local itemIdx, itemMin = minIndex(getItemRatio(targets.items))
    print(string.format("已检测到钻机数量：%d | 采矿机数量：%d", #pumps, #miners))

    if fluidIdx and targets.fluids[fluidIdx] then
        if fluidMin < 1 or allowRandomMine then
            local fluidPara = targets.fluids[fluidIdx].paras
            if fluidPara ~= preFluidPara then
                print(string.format("==================================\n正在调整全部钻机至：%s | 行星：%d | 气体：%d",
                    targets.fluids[fluidIdx].displayName, (fluidPara // 1000) % 100, fluidPara % 1000))
                stopMachine(pumps)
                print("正在修改钻机参数", (fluidPara // 1000) % 100, fluidPara % 1000)
                setPumpParams((fluidPara // 1000) % 100, fluidPara % 1000)
                for _, pump in ipairs(pumps) do pump.setWorkAllowed(true) end
                preFluidPara = fluidPara
            else
                print(string.format("==================================\n钻机参数无需调整，当前正在采集：%s", targets.fluids[fluidIdx].displayName))
            end
        else
            print("当前流体库存充足，无需启动钻机")
            stopMachine(pumps)
        end
    end

    if itemIdx and targets.items[itemIdx] then
        if itemMin < 1 or allowRandomMine then
            local itemPara = targets.items[itemIdx].paras
            if itemPara ~= preItemPara then
                -- v2.2编码：无人机等级×1e8 + 距离×1e5 + 超频×1e4
                local droneLevel = itemPara // 100000000
                local minerDist = (itemPara // 100000) % 1000
                local minerOC = (itemPara % 100000) / 10000
                print(string.format("==================================\n正在调整全部矿机至：%s | 无人机等级：%d | 距离：%d | 超频：%.4f",
                    targets.items[itemIdx].displayName, droneLevel, minerDist, minerOC))
                changeDrone(droneLevel)
                stopMachine(miners)
                print("正在修改矿机参数 距离:", minerDist, "超频:", minerOC)
                setMinerParams(minerDist, minerOC)
                for _, miner in ipairs(miners) do miner.setWorkAllowed(true) end
                preItemPara = itemPara
            else
                print(string.format("==================================\n矿机参数无需调整，当前正在采集：%s", targets.items[itemIdx].displayName))
            end
        else
            print("当前物品库存充足，无需启动矿机")
            stopMachine(miners)
        end
    end

    print("==================================\n调整完成，等待下一周期")
    os.sleep(sleepTime)
end
