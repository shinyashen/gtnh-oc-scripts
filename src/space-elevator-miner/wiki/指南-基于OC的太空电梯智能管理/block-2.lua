
local os = require("os")
local component = require("component")

local sleeptime = 10          -- 检测间隔（秒）
local batchSize = 4           -- 批量处理规模，设为 nil 则不自动设置

function GetUtf8Len(str)
    local len = 0
    local currentIndex = 1
    while currentIndex <= #str do
        local char = string.byte(str, currentIndex)
        currentIndex = currentIndex + (char > 240 and 4 or char > 225 and 3 or char > 192 and 2 or 1)
        len = len + (char > 192 and 2 or 1)
    end
    return len
end

-- ==================== 扫描钻机 ====================
local pumps = {}
for address, name in component.list("gt_machine") do
    local gtm = component.proxy(address)
    local realName = gtm.getName()
    if realName and realName:match("projectmodulepump(.+)$") then
        table.insert(pumps, { machine = gtm, name = realName })
    end
end

-- ==================== 收集缓存器 ====================
local levelMaintainers = {}
for address, name in component.list("level_maintainer") do
    table.insert(levelMaintainers, component.proxy(address))
end
local me = component.me_interface

-- ==================== 读取流体目标 ====================
local function getMonitoringTargets()
    local targets = { fluids = {} }
    local existing = {}
    for _, maintainer in ipairs(levelMaintainers) do
        for slot = 1, 5 do
            local success, slotData = pcall(function() return maintainer.getSlot(slot) end)
            if success and slotData and slotData.isEnable and slotData.isFluid then
                local target = {
                    id          = slotData.fluid and slotData.fluid.name or slotData.name,
                    displayName = slotData.label or slotData.name,
                    buffer      = slotData.quantity or 0,
                    paras       = slotData.batch or 0,
                    isFluid     = true,
                }
                local key = target.id .. tostring(true)
                if not existing[key] then
                    existing[key] = true
                    table.insert(targets.fluids, target)
                    io.write(target.displayName, string.rep(" ", 20 - GetUtf8Len(target.displayName)))
                    print(string.format("%-20d%-20d", target.buffer, target.paras))
                end
            end
        end
    end
    print(string.format("[缓存器] 已读取 %d 个流体监控目标", #targets.fluids))
    return targets
end

-- ==================== 计算流体比例 ====================
local function getFluidRatio(targetFluids)
    if #targetFluids == 0 then return {} end
    local success, fluids = pcall(function() return me.getFluidsInNetwork() end)
    if not success then return {} end
    fluids = fluids or {}
    local ratios = {}
    for idx, tfluid in ipairs(targetFluids) do
        ratios[idx] = 0
        for _, fluid in ipairs(fluids) do
            if fluid and fluid.name == tfluid.id then
                local buffer = tfluid.buffer ~= 0 and tfluid.buffer or 1
                ratios[idx] = fluid.amount / buffer
                if ratios[idx] > 1 and tfluid.paras > 100000 then
                    ratios[idx] = math.huge
                end
                break
            end
        end
    end
    io.write("流体名称：              ")
    for _, t in ipairs(targetFluids) do
        io.write(t.displayName, string.rep(" ", 20 - GetUtf8Len(t.displayName)))
    end
    io.write("\n流体储量与目标值比例：  ")
    for _, r in ipairs(ratios) do
        io.write(string.format("%-20f", r))
    end
    print()
    return ratios
end

-- ==================== 找最小值索引 ====================
local function minIndex(t)
    if #t == 0 then return nil end
    local min_idx, min_val = 1, t[1]
    for i = 2, #t do
        if t[i] < min_val then
            min_val = t[i]
            min_idx = i
        end
    end
    return min_idx, min_val
end

-- ==================== 停机函数 ====================
local function stopMachine(machines)
    print("正在关闭机器")
    for _, machine in ipairs(machines) do
        machine.setWorkAllowed(false)
    end
    local gtmWork = true
    local stoptime = 0
    while gtmWork do
        gtmWork = false
        for _, machine in ipairs(machines) do
            if machine.isMachineActive() then
                gtmWork = true
                break
            end
        end
        os.sleep(1)
        stoptime = stoptime + 1
        if stoptime > 129 then
            print("停机超时")
        end
    end
end

-- ==================== 分配多槽位参数（切配方专用） ====================
local function adjustPumpFluidMultiSlot(pumps, targetFluid)
    local combined = targetFluid.paras
    local planet = math.floor(combined / 1000) % 100
    local gas    = combined % 1000
    print(string.format("正在切换钻机: 星球 %d, 气体 %d (请求值: %d)", planet, gas, combined))

    for _, pump in ipairs(pumps) do
        for i = 0, 6, 2 do 
            pcall(pump.machine.setParameters, i, 0, planet)
            pcall(pump.machine.setParameters, i, 1, gas)
        end
    end
    print("参数下发完成。")
end

-- ==================== 程序启动：一次性设置批处理规模 ====================
print("=== 流体钻机智能管理启动 ===")
print(string.format("检测到 %d 台流体钻机", #pumps))

-- 提取 proxy 列表供关机函数调用
local machineList = {}
for _, p in ipairs(pumps) do table.insert(machineList, p.machine) end

if batchSize and #pumps > 0 then
    stopMachine(machineList)
    for _, p in ipairs(pumps) do
        pcall(p.machine.setParameters, 9, 1, batchSize)
    end
    print("批处理规模初始化完成。")
end

-- ==================== 主循环 ====================
local lastTargetParam = -1

while true do
    if #pumps > 0 then
        local targets = getMonitoringTargets()
        if #targets.fluids > 0 then
            local ratios = getFluidRatio(targets.fluids)
            local idx, minRatio = minIndex(ratios)
            
            if idx then
                local target = targets.fluids[idx]
                
                -- 【核心逻辑 1】：判断当前最紧缺的流体是否充足 (比例 >= 1)
                if minRatio >= 1 then
                    print("当前所有监控流体储量均充足，执行关机并待机。")
                    stopMachine(machineList)
                    -- 关机后直接跳过本次循环剩余的开机/修改参数步骤
                    os.sleep(sleeptime)
                    goto continue
                end
                
                -- 【核心逻辑 2】：流体不足，进行正常处理
                print(string.format("当前最紧缺: %s (比例 %.3f, 参数 %d)", target.displayName, minRatio, target.paras))
                
                -- 只有目标参数发生改变时才执行停机切配方
                if lastTargetParam ~= target.paras then
                    stopMachine(machineList)
                    adjustPumpFluidMultiSlot(pumps, target)
                    lastTargetParam = target.paras
                end
                
                -- 确保机器处于开启状态
                for _, p in ipairs(pumps) do 
                    p.machine.setWorkAllowed(true) 
                end
            end
        else
            print("无流体监控目标，请检查请求器设置。")
        end
    else
        print("未找到任何 projectmodulepump 流体钻机。")
    end
    
    ::continue::
    os.sleep(sleeptime)
end
