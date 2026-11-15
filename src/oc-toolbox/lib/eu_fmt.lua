-- eu_fmt:EU 数值/电压等级/时间格式化(供无线电网监控等工具使用)
-- 逐字拆分自维基《指南:基于OC的无线电网监控》页内脚本(部署版 run.lua),行为保持一致。
local M = {}

-- 小于等于该值时使用逗号三位分隔；大于该值时使用科学计数法
local displayScientificNumbersIfAbove = 1e15
-- MAX电压的大小
local maxVoltageValue = 2147483640
-- GT功率显示会往下显示几个电压等级，方便计算
local GT_SHOW_LOWER = 4

local EU_Monitor = {
    voltageNamesNoColor = {
        "ULV", "LV", "MV", "HV", "EV", "IV",
        "LUV", "ZPM", "UV", "UHV", "UEV", "UIV", "UMV", "UXV"
    },
    maxVoltageNameNoColor = "MAX",
    voltageNames = {},
    maxVoltageName = ""
}

-- 设置各种前景色
local VOLTAGE_NAME_COLOR = "\27[35m"
local SCREEN_RESET_COLOR = "\27[37m"
local SCREEN_GREEN_COLOR = "\27[32m"
local SCREEN_RED_COLOR = "\27[31m"

for _, str in ipairs(EU_Monitor.voltageNamesNoColor) do
    local coloredStr = VOLTAGE_NAME_COLOR .. str .. SCREEN_RESET_COLOR
    table.insert(EU_Monitor.voltageNames, coloredStr)
end
EU_Monitor.maxVoltageName = VOLTAGE_NAME_COLOR .. EU_Monitor.maxVoltageNameNoColor .. SCREEN_RESET_COLOR

function M.formatNumber(number)
    if math.abs(number) > displayScientificNumbersIfAbove then
        return string.format("%.2e", number)
    end
    local i, j, minus, int, fraction = string.format("%.1f", number):find('([-]?)(%d+)([.]?%d*)')
    int = int:reverse():gsub("(%d%d%d)", "%1,") -- reverse the int-string and append a comma to all blocks of 3 digits
    return minus .. int:reverse():gsub("^,", "") -- reverse the int-string back remove an optional comma and put the optional minus and fractional part back
end

function M.extractNumber(alfanum)
    return alfanum:match("([%d,]+)")
end

-- 设置前景色并打印消息
function M.toColorString(value)
    if value == 0 then
        return "0"
    end
    local colorCode = value < 0 and SCREEN_RED_COLOR or SCREEN_GREEN_COLOR  -- 绿色或红色
    return string.format(colorCode.."%s"..SCREEN_RESET_COLOR,M.formatNumber(value))
end

-- 计算GT功率信息
function M.getGTInfo(euPerTick, withColor)
    withColor = withColor == nil or withColor -- default to true
    local voltageNames = withColor and EU_Monitor.voltageNames or EU_Monitor.voltageNamesNoColor
    local maxVoltageName = withColor and EU_Monitor.maxVoltageName or EU_Monitor.maxVoltageNameNoColor
    if euPerTick == 0 then return "0A "..voltageNames[1] end
    local absValue = math.abs(euPerTick)
    local voltage_for_tier = absValue / 2 / (4 ^ GT_SHOW_LOWER)
    -- 处理MAX电压特殊情况
    if absValue >= maxVoltageValue then
        return string.format("%sA "..maxVoltageName, M.formatNumber(absValue/maxVoltageValue))
    end
    -- 计算电压等级
    local tier = voltage_for_tier < 4 and 1 or math.floor(math.log(voltage_for_tier) / math.log(4))
    tier = math.max(1, math.min(tier, #voltageNames))
    -- 处理超出命名范围的情况
    if tier > #EU_Monitor.voltageNames then
        return string.format("%sA "..maxVoltageName, M.formatNumber(absValue/maxVoltageValue))
    end
    -- 计算电流值和电压名称
    local baseVoltage = 8 * (4 ^ (tier - 1))
    local current = absValue / baseVoltage
    return string.format("%.0fA %s", current, voltageNames[tier])
end

-- 计算最后 n 条记录的差值并且得到之间的变化量的平均值（不计入时间间隔，单纯把一前一后两个数的差值除以条目数，请在之后自行除以时间间隔）
function M.calculateAverage(data, n)
    local count = math.min(n, #data)
    if count == 0 then return 0 end
    local now = data[1]
    local prev = data[count]
    return (now-prev) / count
end

--- 将秒数转换为更易读的时间格式
-- @param seconds number 输入的秒数
-- @return string 格式化后的时间字符串
function M.formatTimeFromSeconds(seconds)
    if seconds < 0 then
        return "无效时间"
    end
    if seconds < 60 then return string.format("%.1f 秒", seconds)
    elseif seconds < 3600 then return string.format("%.1f 分钟", seconds / 60)
    elseif seconds < 86400 then return string.format("%.1f 小时", seconds / 3600)
    elseif seconds < 2592000 then return string.format("%.1f 天", seconds / 86400)
    elseif seconds < 31536000 then return string.format("%.1f 月", seconds / 2592000)
    elseif seconds < 31536000 * 1000 then return string.format("%.1f 年", seconds / 31536000)
    else return ">1000年" end
end

return M
