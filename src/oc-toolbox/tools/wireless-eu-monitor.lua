-- 无线电网(兰波顿)EU 功率监控 · 样板OC工具箱合并版
-- 来源:维基《指南:基于OC的无线电网监控》页内脚本(= 上游 fork/wireless-powerd.lua + 6 行分辨率改动)
-- 数据逻辑与上游一致。工具箱化差异(均为独立运行版做不到的增强):
--   1. 后台每秒采样:event.timer 挂常驻采样器,退出监控回菜单后数据窗口与眼镜 HUD 继续更新,
--      只有屏幕绘制暂停(菜单待机时也保持 24h 窗口连续);
--   2. 多 gt_machine 选择:首次运行列出全部 gt_machine 供选择并记住(/home/tools/.monitor.cfg);
--   3. 眼镜自动降级:无 OpenGlasses 组件时仅屏幕输出;退出监控时清空眼镜文字;
--   4. 分辨率保护:进入前保存当前分辨率,退出恢复,避免菜单花屏;
--   5. Q 键返回:监控循环里 Q 与 Ctrl+C 均可退出,回到调用方(工具箱菜单或 shell),
--      退出后菜单立即刷新(标记 ctx.hadSelect 跳过『按任意键』暂停);
--   6. 分钟聚合持久化(/home/tools/.eu_log, ≈29KB): 每运行分钟记一个绝对 EU 值并写盘,
--      重启后 1h/1d 均值与耗尽时间立即恢复(算法与原秒级在无缺口时精确等价),
--      服务器停机期间不产生条目(停机时无线电网不结算,窗口语义=最近 1440 个运行分钟)。
-- 数据源:gt_machine.getSensorInformation()[23] = 无线电网 EU 总量(GTNH 2.7.0 之前是 [19])。
local component = require("component")
local computer = require("computer")
local term = require("term")
local event = require("event")
local fmt = require("eu_fmt")

local M = {
    id = "wireless-eu-monitor",
    name = "无线电网监控",
    group = "监控",
    order = 10,
    desc = "兰波顿无线电网 EU:五档均值/储量/耗尽时间 + 眼镜HUD",
}

-- #region config
local CFG_PATH = "/home/tools/.monitor.cfg"
-- 分钟聚合持久化文件: 每运行分钟记录一次绝对 EU 值, ≤1440 行(=24h) ≈ 29KB
-- 重启后 1h/1d 均值与耗尽时间立即恢复; 5s/1m/5m 短窗口为秒级精度,重启后几分钟自然重建
local HISTORY_PATH = "/home/tools/.eu_log"
local MINUTE_WINDOW = 1440

-- 眼镜文字大小
local textScale = 1
-- 相对屏幕左上角, 眼镜文字横向偏移量
local glassesOffsetX = 3
-- 相对屏幕左上角, 眼镜文字纵向偏移量
local glassesOffsetY = 16
-- 存电只够一小时则红字警告
local exhaustWarningSeconds = 3600
-- #endregion config

-- #region constants
-- 存储多少秒的数据, 内存不足时可以适量改小该值
local SECOND_DATA_SIZE = 3600 * 24
local SCREEN_WIDTH = 60 -- 分辨率(部署版 80×14 → 60×20)
local SCREEN_HEIGHT = 20

local EU_Monitor = {
    secondEU = {},     -- 存储每秒的EU
    secondCounter = 0, -- 秒采样计数(每 60 次记一个分钟点)
    minuteEU = {},     -- 每运行分钟的绝对 EU 值(持久化窗口, [1]=最新)
    last = nil,        -- 最近一次采样结果(均值表)
}

--- @type table<string, Text2D>
local texts = {}

local GLASSES_BLACK_COLOR = { 0, 0, 0 }
local GLASSES_RED_COLOR = { 255, 85, 85 }
local GLASSES_GREEN_COLOR = { 85, 255, 85 }
local GLASSES_WHITE_COLOR = { 255, 255, 255 }

local gpu = component.gpu
-- #endregion constants

-- main loop variable
local doContinue = true
-- run() 全屏循环进行中(后台采样器跳过,避免重复采样)
local active = false
-- 后台采样器定时器 id(首次运行后常驻)
local samplerTimer = nil
-- 选定的 gt_machine(兰波顿电容库适配器)
local chosenAddr = nil
local chosenProxy = nil

do
    local fh = io.open(CFG_PATH, "r")
    if fh then
        local line = fh:read("*l") or ""
        fh:close()
        line = (line:gsub("%s+", ""))
        if line ~= "" then chosenAddr = line end
    end
end

local function saveCfg()
    local ok, fh = pcall(io.open, CFG_PATH, "w")
    if ok and fh then
        fh:write(tostring(chosenAddr or ""))
        fh:close()
    end
end

-- ==== 分钟聚合持久化 ====
-- minuteEU 存绝对 EU 值([1]=最新)。1h 均值 = calculateAverage(minuteEU,60)/60/20,
-- 与原秒级算法在无缺口时精确等价(60 行 × 60s); day 均值同理取 MINUTE_WINDOW 条。
-- 每分钟整文件重写(≈29KB, 任何盘等级放得下), 写盘失败静默跳过不影响运行。
local historyLoaded = false

local function loadHistory()
    if historyLoaded then return end
    historyLoaded = true
    local ok, fh = pcall(io.open, HISTORY_PATH, "r")
    if not ok or not fh then return end
    local lines = {}
    for line in fh:lines() do
        local v = tonumber((line:gsub("%s+", "")))
        if v then lines[#lines + 1] = v end
    end
    fh:close()
    -- 文件按旧→新存, minuteEU[1] 应为最新 → 倒序装入,最多取最后 MINUTE_WINDOW 条
    local start = math.max(1, #lines - MINUTE_WINDOW + 1)
    for i = #lines, start, -1 do
        EU_Monitor.minuteEU[#EU_Monitor.minuteEU + 1] = lines[i]
    end
end

local function saveHistory()
    local rows = EU_Monitor.minuteEU
    if #rows == 0 then return end
    local ok, fh = pcall(io.open, HISTORY_PATH, "w")
    if not ok or not fh then return end
    local buf = {}
    for i = #rows, 1, -1 do  -- 旧→新存盘,便于人工查看
        buf[#buf + 1] = string.format("%.0f", rows[i])
    end
    fh:write(table.concat(buf, "\n") .. "\n")
    fh:close()
end

-- 组件选择:优先用记住的;只有一个直接用;多个列出供选
local function pickGtMachine(ctx)
    local list = {}
    for addr in component.list("gt_machine") do
        list[#list + 1] = addr
    end
    if #list == 0 then
        return nil, "找不到 gt_machine 组件(需要兰波顿超级电容库的适配器)"
    end
    if chosenAddr then
        for _, a in ipairs(list) do
            if a == chosenAddr then
                return component.proxy(a)
            end
        end
    end
    if #list == 1 then
        chosenAddr = list[1]
        saveCfg()
        return component.proxy(list[1])
    end
    local items = {}
    for _, a in ipairs(list) do
        local hint = ""
        local okP, p = pcall(component.proxy, a)
        if okP and p and p.getSensorInformation then
            local okI, info = pcall(p.getSensorInformation)
            if okI and type(info) == "table" and info[23] ~= nil then
                hint = tostring(info[23])
                if #hint > 24 then hint = hint:sub(1, 24) .. ".." end
            end
        end
        items[#items + 1] = { label = a, desc = hint, value = a }
    end
    local pick
    if ctx and ctx.select then
        pick = ctx.select(items, {
            title = "机箱里有 " .. #list .. " 个 gt_machine,选兰波顿电容库的适配器",
            footer = "选中后记住,下次不再问   Q 取消",
        })
    else
        for i, it in ipairs(items) do
            print(string.format("  %d. %s  %s", i, it.label, it.desc))
        end
        local ans = (ctx and ctx.ask and ctx.ask("选哪个（数字）> ", "")) or io.read()
        local n = tonumber(ans or "")
        if n and items[n] then pick = items[n].value end
    end
    if not pick then return nil, "未选择组件" end
    chosenAddr = pick
    saveCfg()
    return component.proxy(pick)
end

local function getWirelessEU()
    if not chosenProxy or not chosenProxy.getSensorInformation then return nil end
    local ok, info = pcall(chosenProxy.getSensorInformation)
    if not ok or type(info) ~= "table" then return nil end
    -- GTNH 2.7.0之前需要将 info[23] 改为 info[19]
    local match = fmt.extractNumber(tostring(info[23] or ""))
    if match then
        local cleanMatch = string.gsub(match, ",", "")
        return tonumber(cleanMatch)
    end
    return nil
end

---@param key string # The key for the text.
---@param x number # The x position of the text.
---@param y number # The y position of the text.
local function createShadowText(glasses, key, x, y)
    y = y * 10
    texts[key .. "shadow"] = glasses.addTextLabel()
    texts[key .. "shadow"].setPosition(x + 1, y + 1)
    texts[key .. "shadow"].setScale(textScale)
    texts[key .. "shadow"].setColor(63 / 255, 63 / 255, 63 / 255)
    texts[key] = glasses.addTextLabel()
    texts[key].setPosition(x, y)
    texts[key].setScale(textScale)
    texts[key].setColor(1, 1, 1)
end

---@param key string # The key for the text.
---@param text string # The text to display.
---@param r number? # The red component from `0` to `255`.
---@param g number? # The green component from `0` to `255`.
---@param b number? # The blue component from `0` to `255 `.
local function setShadowText(key, text, r, g, b)
    if not texts[key] then return end
    texts[key .. "shadow"].setText(text)
    texts[key].setText(text)
    if r == nil or g == nil or b == nil then
        return
    end
    texts[key .. "shadow"].setColor(r / 1028, g / 1028, b / 1028)
    texts[key].setColor(r / 255, g / 255, b / 255)
end

---@param glasses glasses # The glasses component.
local function glassesSetup(glasses)
    glasses.removeAll()
    texts = {}
    createShadowText(glasses, "income_5m", glassesOffsetX, glassesOffsetY + 1)
    createShadowText(glasses, "income_1h", glassesOffsetX, glassesOffsetY + 2)
    createShadowText(glasses, "storage", glassesOffsetX, glassesOffsetY + 3)
    createShadowText(glasses, "exhaustTime", glassesOffsetX, glassesOffsetY + 4)
end

-- 采样一次 + 更新数据窗口 + 刷新眼镜(屏幕绘制只在全屏循环里做)
-- 读取失败(nil)时不插样本不清窗口,保留最后已知状态——旧独立版在此处崩溃(nil 参与算术)
local function sampleAndUpdate()
    local currentEU = getWirelessEU()
    if currentEU == nil then
        EU_Monitor.last = nil
        return
    end
    -- 每秒钟存一个值
    table.insert(EU_Monitor.secondEU, 1, currentEU)
    if #EU_Monitor.secondEU > SECOND_DATA_SIZE then
        table.remove(EU_Monitor.secondEU)
    end
    -- 每满 60 秒记一个分钟点并写盘(持久化 1h/1d 均值窗口)
    EU_Monitor.secondCounter = EU_Monitor.secondCounter + 1
    if EU_Monitor.secondCounter >= 60 then
        EU_Monitor.secondCounter = 0
        table.insert(EU_Monitor.minuteEU, 1, currentEU)
        if #EU_Monitor.minuteEU > MINUTE_WINDOW then
            table.remove(EU_Monitor.minuteEU)
        end
        saveHistory()
    end
    -- 准备输出数据(1h/1d 均值来自持久化分钟窗口: 行距60s, calculateAverage=EU/分钟 → /60s/20t = EU/t)
    local avg = {
        fiveSec = fmt.calculateAverage(EU_Monitor.secondEU, 5) / 20,
        minute  = fmt.calculateAverage(EU_Monitor.secondEU, 60) / 20,
        fiveMin = fmt.calculateAverage(EU_Monitor.secondEU, 300) / 20,
        hour    = fmt.calculateAverage(EU_Monitor.minuteEU, 60) / 60 / 20,
        day     = fmt.calculateAverage(EU_Monitor.minuteEU, MINUTE_WINDOW) / 60 / 20,
    }
    EU_Monitor.last = { currentEU = currentEU, avg = avg }
    -- 绘制眼镜
    -- 无线电网数据更新时间大于1秒，间隔太小没有意义; 蓝波顿上传间隔是5分钟，取5分钟可以避免蓝波顿上传带来的峰，这里取5分钟均值和小时均值
    -- 耗尽时间基于小时均值计算，小于一小时则红字报警
    local exhaustSeconds = currentEU / (-avg.hour) / 20
    setShadowText("income_5m", string.format("5m: %s EU/t (%s)", fmt.formatNumber(avg.fiveMin), fmt.getGTInfo(avg.fiveMin, false)),
        table.unpack(avg.fiveMin < 0 and GLASSES_RED_COLOR or avg.fiveMin > 0 and GLASSES_GREEN_COLOR or GLASSES_WHITE_COLOR))
    setShadowText("income_1h", string.format("1h: %s EU/t (%s)", fmt.formatNumber(avg.hour), fmt.getGTInfo(avg.hour, false)),
        table.unpack(avg.hour < 0 and GLASSES_RED_COLOR or avg.hour > 0 and GLASSES_GREEN_COLOR or GLASSES_WHITE_COLOR))
    setShadowText("storage", string.format("储量: %s EU", fmt.formatNumber(currentEU)))
    setShadowText("exhaustTime", ("耗尽时间: " .. ((exhaustSeconds <= 0) and "N/A" or fmt.formatTimeFromSeconds(exhaustSeconds))),
        table.unpack((exhaustSeconds > 0 and exhaustSeconds < exhaustWarningSeconds) and GLASSES_RED_COLOR or GLASSES_WHITE_COLOR))
end

-- 全屏绘制(与独立运行版逐行一致)
local function drawScreen()
    local last = EU_Monitor.last or { currentEU = nil, avg = {} }
    local currentEU = last.currentEU
    local avg = last.avg
    if currentEU == nil then
        term.clear()
        print("存量: 读取失败(检查兰波顿电容库的适配器组件)")
        print("(按 Q 或 Ctrl+C 返回)")
        return
    end
    term.clear()
    print(string.format("存量: %.2e EU", currentEU))
    print(string.format("可用功率(秒): %.1e EU/s (%s)", currentEU/20, fmt.getGTInfo(currentEU/20)))
    print(string.format("可用功率(小时): %.1e EU/hour (%s)", currentEU/3600/20, fmt.getGTInfo(currentEU/3600/20)))
    print(string.format("可用功率(天): %.1e EU/day (%s)", currentEU/3600/20/24, fmt.getGTInfo(currentEU/3600/20/24)))
    print()
    print(string.format("每五秒均值: %s EU/t (%s)", fmt.toColorString(avg.fiveSec or 0), fmt.getGTInfo(avg.fiveSec or 0)))
    print(string.format("每分钟均值: %s EU/t (%s)", fmt.toColorString(avg.minute or 0), fmt.getGTInfo(avg.minute or 0)))
    print(string.format("五分钟均值: %s EU/t (%s)", fmt.toColorString(avg.fiveMin or 0), fmt.getGTInfo(avg.fiveMin or 0)))
    print(string.format("每小时均值: %s EU/t (%s)", fmt.toColorString(avg.hour or 0), fmt.getGTInfo(avg.hour or 0)))
    print(string.format("每天均值: %s EU/t (%s)", fmt.toColorString(avg.day or 0), fmt.getGTInfo(avg.day or 0)))
    print()
    print("(按 Q 或 Ctrl+C 返回)")
end

-- 捕获 Ctrl+C 事件进行优雅关机
local function onInterrupted()
    doContinue = false
end

-- 注册后台每秒采样器(幂等):菜单/其他工具界面挂机时窗口与眼镜照常更新
local function ensureSampler()
    if samplerTimer then return end
    samplerTimer = event.timer(1, function()
        if active then return end
        if not chosenProxy then return end
        pcall(sampleAndUpdate)
    end, math.huge)
end

function M.run(ctx, args)
    args = args or {}
    ctx = ctx or {}
    -- 全屏交互工具:标记后菜单返回时跳过"按任意键"暂停(bin/toolbox runOne)
    ctx.hadSelect = true
    -- 组件选择
    local proxy, err = pickGtMachine(ctx)
    if not proxy then
        if ctx.select then
            ctx.select({ { label = "知道了", value = 1 } }, {
                title = "无法开始监控",
                footer = tostring(err),
            })
        else
            (ctx.write or print)(tostring(err))
        end
        return false
    end
    chosenProxy = proxy

    -- 眼镜(没有则自动降级为仅屏幕)
    local glasses = nil
    do
        local ok, g = pcall(function() return component.glasses end)
        if ok and g then glasses = g end
    end

    -- 分辨率保存
    local oldW, oldH
    if gpu then
        local ok, w, h = pcall(function() return gpu.getResolution() end)
        if ok then oldW, oldH = w, h end
    end

    doContinue = true
    event.listen("interrupted", onInterrupted)
    if glasses then glassesSetup(glasses) end
    if gpu then pcall(gpu.setViewport, SCREEN_WIDTH, SCREEN_HEIGHT) end
    term.clear()
    term.setCursorBlink(false)
    loadHistory()
    ensureSampler()
    active = true

    -- 主循环,每秒采样刷新一次;Q / Ctrl+C 随时返回上层(菜单或 shell)
    while doContinue do
        sampleAndUpdate()
        drawScreen()
        local deadline = computer.uptime() + 1
        repeat
            local ev = { event.pull(0.2) }
            if ev[1] == "key_down" and (ev[3] == 113 or ev[3] == 81) then
                doContinue = false
            elseif ev[1] == "interrupted" then
                doContinue = false
            end
        until (not doContinue) or computer.uptime() >= deadline
    end

    active = false
    -- 取消事件监听, 防止多次启动脚本后重复注册
    event.ignore("interrupted", onInterrupted)
    -- 退出清理:清眼镜文字、恢复分辨率
    if glasses then pcall(glasses.removeAll) end
    texts = {}
    if oldW and gpu then pcall(gpu.setViewport, oldW, oldH) end
    term.setCursorBlink(false)
    return true
end

return M
