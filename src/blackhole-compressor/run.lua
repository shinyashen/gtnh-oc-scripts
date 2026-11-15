local component = require("component")
local computer = require("computer")
local sides = require("sides")
local event = require("event")

-- ################ 红石端口配置（单端口，按“面”区分输出/输入） ################
-- 红石 I/O 端口地址：电脑上只连了一个 redstone 组件时可以留空（自动使用 component.redstone）；
-- 若还接了别的红石组件（红石卡等），请用 `components` 命令查到地址后填在这里
local rsAddr = ""
-- 输出面：时空红石信号（原来 rsSideSpcaeTime 接的那一面）
local rsSideSpcaeTime = sides.south
-- 输入面：黑洞多功能仓(静态模式)信号输入面（不能包含上面的输出面）
-- 16 台黑洞的信号可以几台并一根线接到任意输入面；脚本只判断“全部为 0 = 全部关闭”
local feedbackSides = { sides.north, sides.east, sides.west, sides.up, sides.down }
-- 方案A开关：true=用黑洞反馈确认“全部关闭”后才切断时空；false=退回旧逻辑（等 5s）
local useFeedback = true
-- 关闭黑洞最长等待(秒)：只用于屏幕报警；超时也不会切断时空信号，会继续补投重试
local closeTimeout = 250
-- ##############################################################################

-- ================= 方向配置 =================
local sourceSide = sides.south      -- 转运输入方向
local targetSide = sides.down       -- 转运输出方向
local seedSlot = 1                  -- 黑洞种子的槽位
local collapseSlot = 2              -- 黑洞坍缩器的槽位

local maxTime = 275                 -- 黑洞稳定时间过长，重启黑洞的时间
-- ============================================

local machineList = {}
for address, _ in component.list("gt_machine") do
    if component.invoke(address, "getName") == "multimachine.blackholecompressor" then
        table.insert(machineList, address)
    end
end

local me_controller = component.me_controller
local transposer = component.transposer

local targetSlot = transposer.getInventorySize(targetSide) > 2 and 2 or 1 -- 共享输入总线槽1不可用

-- ===== 红石端口解析 =====
local function listRedstoneAddresses()
    local list = {}
    for address, _ in component.list("redstone") do
        list[#list + 1] = address
    end
    return list
end

local function resolveRedstone(addr)
    local ok, proxy = pcall(component.proxy, addr)
    if ok and type(proxy) == "table" and type(proxy.getInput) == "function"
        and type(proxy.setOutput) == "function" then
        return proxy
    end
    return nil
end

local redstoneAddresses = listRedstoneAddresses()
local redstone
if rsAddr ~= nil and rsAddr ~= "" then
    redstone = resolveRedstone(rsAddr)
else
    redstone = component.redstone
end

local feedbackOk = useFeedback and (redstone ~= nil)

-- 反馈要读的面（排除输出面，避免把脚本自己输出的时空信号当成“黑洞还开着”）
local feedbackReadSides = {}
for _, side in ipairs(feedbackSides) do
    if side ~= rsSideSpcaeTime then
        feedbackReadSides[#feedbackReadSides + 1] = side
    end
end

local function countOpenSides()
    if not feedbackOk then return 0 end
    local count = 0
    for _, side in ipairs(feedbackReadSides) do
        if (redstone.getInput(side) or 0) > 0 then
            count = count + 1
        end
    end
    return count
end

local time1, time2, maxProgress, timerID = 0, 0, 0, nil
local status, empty = "[空闲]", function() return "" end
local getInfo = empty
local gpu = component.gpu
gpu.setViewport(32, 10)
gpu.setForeground(0x00FF00)
local gpuTimerID = event.timer(0.5, function()
    local line = string.format("状态：%s", status)
    gpu.set(1, 2, line .. string.rep(" ", math.max(0, 32 - #line)))
    line = getInfo()
    gpu.set(1, 3, line .. string.rep(" ", math.max(0, 32 - #line)))
    if feedbackOk then
        local open = countOpenSides()
        gpu.set(1, 4, string.rep(" ", 32))
        gpu.setForeground(open > 0 and 0xFFFF00 or 0x00FF00)
        gpu.set(1, 4, string.format("反馈 开洞面:%d/%d", open, #feedbackReadSides))
        gpu.setForeground(0x00FF00)
    end
end, math.huge)
gpu.set(1, 1, "黑洞数量："..tostring(#machineList).."                     ")
for i=2,10 do
    gpu.set(1, i, string.rep(" ", 32))
end

-- ===== 启动自检 =====
if redstone == nil then
    gpu.setForeground(0xFF0000)
    gpu.set(1, 2, "错误：未找到 redstone 组件")
    gpu.setForeground(0x00FF00)
    error("未找到 redstone 组件，请检查红石 I/O 端口/线缆，或在配置里填写 rsAddr")
end
if rsAddr ~= nil and rsAddr ~= "" and resolveRedstone(rsAddr) == nil then
    gpu.setForeground(0xFF0000)
    gpu.set(1, 2, "错误：rsAddr 地址无效")
    gpu.setForeground(0x00FF00)
    error("rsAddr 地址无效，请用 components 命令或分析器重新复制")
end
if #redstoneAddresses > 1 and (rsAddr == nil or rsAddr == "") then
    local lines = { "# 检测到多个 redstone 组件，component.redstone 可能选错端口（选错会导致时空信号发到错的端口）", "# 把要用的红石 I/O 地址填到 run.lua 的 rsAddr", "" }
    for _, address in ipairs(redstoneAddresses) do
        lines[#lines + 1] = address
    end
    local ok, file = pcall(io.open, "/home/redstone_ports.txt", "w")
    if ok and file then
        file:write(table.concat(lines, "\n") .. "\n")
        file:close()
    end
    gpu.setForeground(0xFF0000)
    gpu.set(1, 6, "检测到多个红石组件")
    gpu.set(1, 7, "请把红石 I/O 地址填到 rsAddr")
    gpu.set(1, 8, "地址见 redstone_ports.txt")
    gpu.setForeground(0x00FF00)
    error("检测到多个 redstone 组件，请在配置里填写 rsAddr（地址见 /home/redstone_ports.txt）")
end

-- ===== 工具函数 =====
local function setWorkAllowed(work)
    for _, address in ipairs(machineList) do
        component.invoke(address, "setWorkAllowed", work)
    end
end

local function transferItem(side1, side2, size, slot1, slot2)
    if transposer.transferItem(side1, side2, size, slot1, slot2) == 0 then
        transposer.transferItem(side2, side1, 64, slot2)
        transposer.transferItem(side1, side2, size, slot1, slot2)
    end
end

local function getAnyProgress()
    for _, address in ipairs(machineList) do
        if component.invoke(address, "getWorkProgress") ~= 0 then
            return true
        end
    end
    return false
end

local function getSourceCount(slot)
    local ok, count = pcall(transposer.getSlotStackSize, sourceSide, slot)
    if ok and type(count) == "number" then return count end
    return 0
end

local function getBusCollapserCount()
    local ok, count = pcall(transposer.getSlotStackSize, targetSide, targetSlot)
    if ok and type(count) == "number" then return count end
    return 0
end

-- 等所有机器都空闲（没有配方在跑）并持续 idleFor 秒
local function waitAllIdle(idleFor, timeout)
    local start = computer.uptime()
    local idleSince = nil
    while computer.uptime() - start < timeout do
        if getAnyProgress() then
            idleSince = nil
        else
            idleSince = idleSince or computer.uptime()
            if computer.uptime() - idleSince >= idleFor then
                return true
            end
        end
        os.sleep(0.5)
    end
    return false
end

-- 等待反馈确认所有黑洞关闭；wave = 每次补投的坍缩器数量
local function waitAllClosed(wave)
    if not feedbackOk then
        os.sleep(5) -- 旧行为：没有反馈时等 5s
        return
    end
    local race = (wave > 1)
    local startTime = computer.uptime()
    local quietSince = nil
    local warned = false
    local function countProcessing()
        local n = 0
        for _, address in ipairs(machineList) do
            if component.invoke(address, "getWorkProgress") ~= 0 then
                n = n + 1
            end
        end
        return n
    end
    local function refill(n)
        if getSourceCount(collapseSlot) < 1 then
            getInfo = function() return "黑洞坍缩器不足，等待补充" end
            return false
        end
        transferItem(sourceSide, targetSide, n, collapseSlot, targetSlot)
        return true
    end
    getInfo = function()
        return string.format("等待黑洞关闭 (开=%d面 %ds)", countOpenSides(), math.floor(computer.uptime() - startTime))
    end
    while true do
        local open = countOpenSides()
        local busy = getAnyProgress()
        if open > 0 or busy then
            quietSince = nil
        elseif quietSince == nil then
            quietSince = computer.uptime()
        elseif computer.uptime() - quietSince >= 3 then
            -- 反馈连续 3 秒全 0 且没有机器在跑配方，才认为全部关闭
            break
        end
        if race then
            local processing = countProcessing()
            if processing > 0 then
                -- 禁用空闲机器（基本都是已关掉的），避免它们把坍缩器白吃掉
                for _, address in ipairs(machineList) do
                    if component.invoke(address, "getWorkProgress") == 0 then
                        component.invoke(address, "setWorkAllowed", false)
                    end
                end
                if open > 0 and getBusCollapserCount() == 0 then
                    refill(processing + 1)
                end
            else
                -- 没有机器在跑配方但还有洞开着：恢复所有机器（让空闲开洞的机器也能做检查）
                for _, address in ipairs(machineList) do
                    component.invoke(address, "setWorkAllowed", true)
                end
                if open > 0 and getBusCollapserCount() == 0 then
                    refill(wave)
                end
            end
        else
            if (open > 0 or busy) and getBusCollapserCount() == 0 then
                refill(wave)
            end
        end
        if not warned and computer.uptime() - startTime > closeTimeout then
            warned = true
            status = "[警告]"
        end
        getInfo = function()
            return string.format("等待黑洞关闭 (开=%d面 %ds)", open, math.floor(computer.uptime() - startTime))
        end
        os.sleep(1)
    end
    -- 关闭完成后恢复所有机器（反正紧接着会 setWorkAllowed(false)）
    for _, address in ipairs(machineList) do
        component.invoke(address, "setWorkAllowed", true)
    end
    getInfo = empty
    status = "[关闭中]"
end

local function turnOff()
    for _, address in ipairs(machineList) do
        local progress = component.invoke(address, "getWorkMaxProgress") - component.invoke(address, "getWorkProgress")
        if progress > maxProgress then
            maxProgress = progress
        end
    end
    time2 = computer.uptime()
    local clean = false
    if feedbackOk then
        -- 子网已经没料时，先等所有机器把最后一批配方跑完、并安静 6 秒再投坍缩器，
        -- 这样每台机器的周期检查会 1:1 各吃一个，避免已关掉的机器把坍缩器白吃掉。
        if me_controller.getItemsInNetwork()[1] == nil and me_controller.getFluidsInNetwork()[1] == nil then
            getInfo = function() return "等待机器空闲 ("..tostring(math.floor(computer.uptime() - time2)).."s)" end
            clean = waitAllIdle(6, 90)
        end
    end
    transferItem(sourceSide, targetSide, #machineList, collapseSlot, targetSlot) -- 先投入坍缩器，配方结束时自动关闭黑洞
    if feedbackOk then
        -- 干净模式：只补投 1 个；有配方在跑的模式：每次补投一整批，抢在机器配方结束前投进去
        waitAllClosed(clean and 1 or #machineList)
    else
        getInfo = function() return "等待配方结束 ("..tostring(math.floor(computer.uptime() - time2)).."/"..tostring(math.ceil(maxProgress/20))..")" end
        while getAnyProgress() do
            os.sleep(1)
        end
        os.sleep(5) --硬编码等待5s以等待主机识别坍缩器
    end
    getInfo = empty
    setWorkAllowed(false)
    if timerID then
        event.cancel(timerID)
        timerID = nil
    end
    redstone.setOutput(rsSideSpcaeTime, 0)
end

local function main()
    -- 启动时如果还有黑洞开着：先保持时空信号并关掉它们，避免直接断时空导致失稳吞材料
    if feedbackOk and countOpenSides() > 0 then
        redstone.setOutput(rsSideSpcaeTime, 15)
        setWorkAllowed(true)
        status = "[恢复]"
        getInfo = function() return "启动时检测到残留黑洞，先关闭" end
        turnOff()
    else
        redstone.setOutput(rsSideSpcaeTime, 0)
    end
    setWorkAllowed(false)
    while true do
        os.sleep(3)
        ::redo::
        -- 上一轮有黑洞没关干净时，先关掉再开新的（关闭需要机器能做配方检查，所以先允许工作）
        if feedbackOk and countOpenSides() > 0 then
            status = "[恢复]"
            getInfo = function() return "检测到残留黑洞，先关闭" end
            setWorkAllowed(true)
            turnOff()
        end
        if transposer.getSlotStackSize(sourceSide,seedSlot)<#machineList or transposer.getSlotStackSize(sourceSide,collapseSlot)<#machineList then
            status = "[错误]"
            getInfo = function() return "黑洞种子 或 黑洞坍缩器 数量不足" end
            while true do
                os.sleep(5)
                if transposer.getSlotStackSize(sourceSide,seedSlot)>=#machineList and transposer.getSlotStackSize(sourceSide,collapseSlot)>=#machineList then
                    status = "[空闲]"
                    getInfo = empty
                    break
                end
            end
        end
        if me_controller.getItemsInNetwork()[1] ~= nil or me_controller.getFluidsInNetwork()[1] ~= nil then
            transferItem(sourceSide, targetSide, #machineList, seedSlot, targetSlot)
            setWorkAllowed(true)
            status = "[运行中]"
            time1 = computer.uptime()
            if feedbackOk then
                -- 用反馈确认种子生效：任意一面亮起即说明至少开了一个洞
                local checkStart = computer.uptime()
                while feedbackOk and countOpenSides() == 0 and computer.uptime() - checkStart < 4 do
                    os.sleep(0.5)
                end
                if countOpenSides() == 0 then
                    feedbackOk = false
                    status = "[警告]"
                    getInfo = function() return "未检测到反馈信号，退回旧关闭逻辑" end
                    os.sleep(3)
                    status = "[运行中]"
                end
            end
            getInfo = function() return "等待稳定度下降 ("..tostring(math.floor(computer.uptime() - time1)).."/90)" end
            timerID = event.timer(90, function()
                redstone.setOutput(rsSideSpcaeTime, 15)
                timerID = nil
            end)
            while timerID do
                os.sleep(1)
                --[[稳定度下降期间不消耗时空，不必关闭黑洞
                if me_controller.getItemsInNetwork()[1] == nil and me_controller.getFluidsInNetwork()[1] == nil then
                    status = "[关闭中]"
                    turnOff() -- 使用timer，确保等待最后一轮配方期间，在稳定度降到10时仍能开启时空输入
                    status = "[空闲]"
                    goto redo
                end
                ]]--
            end
            time1 = computer.uptime()
            getInfo = function() return "正在运行 ("..tostring(math.floor(computer.uptime() - time1)).."/"..tostring(maxTime)..")" end
            while me_controller.getItemsInNetwork()[1] ~= nil or me_controller.getFluidsInNetwork()[1] ~= nil do
                if computer.uptime() >= time1 + maxTime then
                    status = "[重启中]"
                    turnOff()
                    goto redo
                end
                os.sleep(1)
            end
            status = "[关闭中]"
            turnOff()
            status = "[空闲]"
        end
    end
end

local _, err = pcall(main)
event.cancel(gpuTimerID)
local stillOpen = feedbackOk and countOpenSides() > 0
setWorkAllowed(false)
-- 最多等 10s 让当前配方收尾（避免残留进度导致死等）
local stopDeadline = computer.uptime() + 10
while getAnyProgress() and computer.uptime() < stopDeadline do
    os.sleep(0.5)
end
if stillOpen then
    -- 程序异常退出且仍有黑洞没关时：保持时空信号，冻结稳定度，等下次启动再关闭
    redstone.setOutput(rsSideSpcaeTime, 15)
    gpu.setForeground(0xFF0000)
    gpu.set(1, 2, "错误: " .. tostring(err))
    gpu.set(1, 3, "仍有黑洞未关闭，时空信号保持开启")
    gpu.set(1, 4, "请检查后重启程序")
    gpu.setForeground(0xFFFFFF)
    gpu.setViewport(gpu.getResolution())
    error(err)
else
    redstone.setOutput(rsSideSpcaeTime, 0)
    gpu.setForeground(0xFFFFFF)
    gpu.setViewport(gpu.getResolution())
    error(err)
end
