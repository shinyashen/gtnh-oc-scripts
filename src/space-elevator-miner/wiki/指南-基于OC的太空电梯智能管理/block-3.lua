
local os = require("os")
local component = require("component")
local sides = require("sides")
 
local sideDrone=sides.down                --无人机的末影箱子的方向
local sideInput=sides.up                  --输入总线的方向
local sleeptime=10                        --检测间隔
local pumpBatch=64                       --此处可设置所有钻机批处理数。设为nil时关闭自动设置。
local plasmaLevel=5                       --此处可设置所有矿机使用的等离子以计算OC，氦等为1，钚等为5。设为nil时关闭自动设置。
local minerOC=not plasmaLevel or 2.12-0.194*plasmaLevel    
 
-- ===== 新增：初始化fluid_interface组件 =====
local fluidInterface = nil
local function initializeFluidInterface()
    local fluidAddr = component.list("fluid_interface")()
    if fluidAddr then
        fluidInterface = component.proxy(fluidAddr)
        print("成功连接到fluid_interface: " .. fluidAddr)
        return true
    else
        print("警告：未找到fluid_interface流体接口设备，流体读取功能将不可用")
        return false
    end
end

-- ===== 新增：参考文件的流体读取函数 =====
local function getFluidAmount(fluidName)
    if not fluidInterface then return 0 end

    local success, fluidDetail = pcall(fluidInterface.getFluidInNetwork, fluidName)
    if success and fluidDetail and next(fluidDetail) ~= nil then
        return math.max(0, fluidDetail.amount or 0)
    end

    return 0
end

local function getAllFluids()
    if not fluidInterface then return {} end

    local success, allFluids = pcall(fluidInterface.getFluidsInNetwork)
    local result = {}
    if success and type(allFluids) == "table" and #allFluids > 0 then
        for _, fluid in ipairs(allFluids) do
            result[fluid.name] = fluid.amount or 0
        end
    end
    return result
end
 
local pumps = {}
local miners = {}
for address, name in component.list("gt_machine") do
    local gtm = component.proxy(address)
    if gtm.getName():match("projectmodulepump(.+)$") then table.insert(pumps, gtm) end
    if gtm.getName():match("projectmoduleminer(.+)$") then table.insert(miners, gtm) end
end
 
local levelMaintainers = {}
for address, name in component.list("level_maintainer") do
    local maintainer = component.proxy(address)
    table.insert(levelMaintainers, maintainer)
end
local transposers = {}
for address, name in component.list("transposer") do
    local transposer = component.proxy(address)
    table.insert(transposers, transposer)
end
-- ===== 移除me_interface，改用fluid_interface =====
-- local me=component.me_interface
 
function GetUtf8Len(str)--获取包含中文的字符串的显示宽度
    local len = 0 
    local currentIndex = 1 
    while currentIndex <= #str do 
        local char = string.byte(str,currentIndex) 
        currentIndex=currentIndex+(char>240 and 4 or char>225 and 3 or char>192 and 2 or 1)
        len = len + (char>192 and 2 or 1)
    end 
    return len 
end
 
local function getMonitoringTargets()
    local targets = {items = {}, fluids = {} }
    local processedCount = 0
    -- 去重哈希表：确保相同目标只读取一次
    local existingTargets = {}
    
    for _, maintainer in ipairs(levelMaintainers) do
        for slot = 1, 5 do
            local success, slotData = pcall(function() 
                return maintainer.getSlot(slot) 
            end)
            if success and slotData then
                if slotData.isEnable then
                    local target = {
                        id = slotData.name,
                        displayName = slotData.label or slotData.name,
                        buffer = slotData.quantity or 0,
                        paras = slotData.batch or 0,
                        isFluid = slotData.isFluid or false
                    }
                    
                    -- 第一步：先完整解析目标信息（流体/物品）
                    if target.isFluid then
                        target.id = slotData.fluid and slotData.fluid.name or slotData.name
                    else
                        target.damage = slotData.damage or 0
                        local nameFromID, damageFromID = target.id:match("^(.+):(%d+)$")
                        if nameFromID and damageFromID then
                            target.name = nameFromID
                            target.damage = tonumber(damageFromID)
                        else
                            target.name = target.id
                        end
                        if slotData.damage and slotData.damage > 0 then 
                            target.damage = slotData.damage 
                        end
                    end
                    
                    -- 第二步：生成唯一标识（核心修复：统一在解析后生成，避免覆盖）
                    local uniqueKey = target.id .. (target.damage or 0) .. tostring(target.isFluid)
                    
                    -- 第三步：仅当目标未存在时才添加和打印
                    if not existingTargets[uniqueKey] then
                        existingTargets[uniqueKey] = true  -- 标记为已读取
                        
                        -- 添加到目标列表
                        if target.isFluid then
                            table.insert(targets.fluids, target)
                        else
                            table.insert(targets.items, target)
                        end
                        processedCount = processedCount + 1
                        
                        -- 打印目标信息（仅非重复目标）
                        io.write(target.displayName,string.rep(" ", 20-GetUtf8Len(target.displayName)))
                        print(string.format("%-20d%-20d",target.buffer,target.paras))
                    end
                end
            else
                if not success then
                    print(string.format("[警告] 获取缓存器槽位 %d 数据失败: %s", slot, tostring(slotData)))
                end
            end
        end
    end
    print(string.format("[缓存器] 已读取 %d 个监控目标 (%d 物品, %d 流体)", 
          processedCount, #targets.items, #targets.fluids))
    
    return targets
end
 
local function getFluidRatio(targetFluids)
    -- 空流体目标时返回空表，避免报错
    if #targetFluids == 0 then
        return {}
    end
    
    -- ===== 替换为fluid_interface读取方式 =====
    local stockRatio={}
    for _, tfluid in ipairs(targetFluids) do
        local currentAmount = getFluidAmount(tfluid.id)
        -- 除以0保护
        local buffer = tfluid.buffer ~= 0 and tfluid.buffer or 1
        stockRatio[_] = currentAmount / buffer
        if stockRatio[_]>1 and tfluid.paras>100000 then 
            stockRatio[_] = math.huge 
        end
    end
    
    io.write("流体名称：              ")
    for _, tfluid in ipairs(targetFluids) do 
        io.write(tfluid.displayName,string.rep(" ",20-GetUtf8Len(tfluid.displayName))) 
    end
    io.write("\n流体储量与目标值比例：  ")
    for _, stockRatio1 in ipairs(stockRatio) do 
        io.write(string.format("%-20f",stockRatio1)) 
    end
    print()
    return stockRatio
end
 
local function getItemRatio(targetItems) 
    -- ===== 物品仍保留原逻辑（如需替换可参考fluid逻辑，改用item_interface）=====
    local stockRatio={}
    -- 兼容处理：如果没有me_interface则提示并返回空
    local me = component.isAvailable("me_interface") and component.proxy(component.list("me_interface")()) or nil
    if not me then
        print("警告：未找到me_interface，物品读取功能不可用")
        return stockRatio
    end

    for _, item in ipairs(targetItems) do
        local filter = {name = item.name}
        if item.damage and item.damage > 0 then filter.damage = item.damage end
        
        local success, items = pcall(function() return me.getItemsInNetwork(filter) end)
        if not success then 
            print("寻找:",item.name,item.damage,item.displayName,"时出错，退出程序")
            os.exit(114514)
        end
        
        items = items or {}
        local currentAmount = 0
        
        for __, itemStack in ipairs(items) do
            if itemStack and itemStack.name == item.name and (itemStack.damage or 0) == item.damage then
                currentAmount = currentAmount + (itemStack.size or 0)
            end
        end
        -- 除以0保护
        local buffer = item.buffer ~= 0 and item.buffer or 1
        table.insert(stockRatio,currentAmount/buffer)
        if stockRatio[_]>1 and item.paras>100000 then stockRatio[_]=math.huge end
    end
    io.write("物品名称：              ")
    for _, tItem in ipairs(targetItems) do io.write(tItem.displayName,string.rep(" ",20-GetUtf8Len(tItem.displayName))) end
    io.write("\n物品储量与目标值比例：  ")
    for _, stockRatio1 in ipairs(stockRatio) do io.write(string.format("%-20f",stockRatio1)) end
    print()
    return stockRatio
end
 
local function minIndex(t)
    -- 空表返回nil，避免索引错误
    if #t == 0 then return nil end
    local min_idx = 1
    local min_val = t[1]
    for i = 2, #t do
        if t[i] < min_val then
            min_val = t[i]
            min_idx = i
        end
    end
    return min_idx, min_val
end
 
local function stopMachine(machines)
    print("正在关闭机器")
    for _,machine in ipairs(machines) do machine.setWorkAllowed(false) end
    local gtmWork=true
    local stoptime=0
    while gtmWork do                                    
        gtmWork=false
        for _,machine in ipairs(machines) do
            if machine.isMachineActive() then 
                gtmWork=true 
                break
            end
        end
        os.sleep(1)    
        stoptime=stoptime+1
        if stoptime>129 then 
            print("停机超时")
        end
    end
end
 
local function adjustPumpFluid(pumps,param1, param2)
    print("正在修改钻机参数",param1,param2)
    for _,pump in ipairs(pumps) do
        for i = 0,6,2 do 
            pcall(pump.setParameters, i, 0, param1)
            pcall(pump.setParameters, i, 1, param2)
        end
    end
end
 
local function adjustParameters(machines,idx1,idx2,param)
    print("正在修改参数",idx1,idx2,param)
    for _,machine in ipairs(machines) do
        pcall(machine.setParameters, idx1, idx2, param)
    end
end
 
local function searchDrone(droneLevel)
    local slotDataAll=transposers[1].getAllStacks(sideDrone).getAll()
    for slotIdx,slotData in pairs(slotDataAll) do
        if slotData.name=="gtnhintergalactic:item.MiningDrone" and slotData.damage==droneLevel-1 then
            return slotIdx,slotData.size
        end
    end
    print("目标采矿无人机不足，随机选择其他采矿机填充")
    for slotIdx,slotData in pairs(slotDataAll) do
        if slotData.name=="gtnhintergalactic:item.MiningDrone"then return slotIdx,slotData.size end
    end
end
local function moveDrone(droneLevel)
    print("正在移动无人机，等级：",droneLevel)
    local droneCount,droneSlot=0,0
    for _,transposer in ipairs(transposers) do
        transposer.transferItem(sideInput,sideDrone)
    end
    for _,transposer in ipairs(transposers) do
        if droneCount==0 then
            droneSlot,droneCount=searchDrone(droneLevel)
            droneSlot=droneSlot+1
        end
        if droneCount==0 then break end  
        transposer.transferItem(sideDrone,sideInput,1,droneSlot)
        droneCount=droneCount-1
    end
end

-- ===== 程序启动时初始化fluid_interface =====
initializeFluidInterface()

if pumpBatch then 
    stopMachine(pumps)
    adjustParameters(pumps,9,1,pumpBatch) 
end
if plasmaLevel then adjustParameters(miners,1,0,minerOC) end
local preFluidPara,preItemPara=0,0
while true do
    os.execute("cls")        
    print("太空电梯智能控制系统\n==================================\n正在读取监控目标")
    local targets=getMonitoringTargets()
    print("==================================\n正在读取当前库存")
    local fluidIdx,_=minIndex(getFluidRatio(targets.fluids))
    local itemIdx,_=minIndex(getItemRatio(targets.items))
    
    -- 检查fluidIdx有效性，避免nil索引
    if fluidIdx and targets.fluids[fluidIdx] then
        local fluidPara=targets.fluids[fluidIdx].paras
        if fluidPara~=preFluidPara then
            print("==================================\n正在调整钻机至：",targets.fluids[fluidIdx].displayName,"参数：",fluidPara)
            stopMachine(pumps)
            adjustPumpFluid(pumps,(fluidPara//1000)%100,fluidPara%1000)
            for _,pump in ipairs(pumps) do pump.setWorkAllowed(true) end
            preFluidPara=fluidPara
        end
    end
    
    -- 检查itemIdx有效性，避免nil索引
    if itemIdx and targets.items[itemIdx] then
        local itemPara=targets.items[itemIdx].paras
        if itemPara~=preItemPara then
            print("==================================\n正在调整矿机至：",targets.items[itemIdx].displayName,"参数：",itemPara)
            if (itemPara//1000)%100~=(preItemPara//1000)%100 then
                moveDrone((itemPara//1000)%100)
            end
            if itemPara%1000~=preItemPara%1000 then
                stopMachine(miners)
                adjustParameters(miners,0,0,itemPara%1000)
                for _,miner in ipairs(miners) do miner.setWorkAllowed(true) end
            end
            preItemPara=itemPara
        end
    end
    
    print("==================================\n调整完成，等待下一周期")
    os.sleep(sleeptime)
end
