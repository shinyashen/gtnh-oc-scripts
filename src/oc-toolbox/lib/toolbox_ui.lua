-- toolbox_ui:屏幕绘制与输入公共层(THEME 配色/色深降级/宽字符处理/点击命中测试)
-- 拆分自上游单文件版《样板OC工具箱》主程序,行为保持一致。
local component = require("component")
local term = require("term")
local event = require("event")

local M = {}

local gpu = component.gpu
M.W, M.H = 80, 25
if gpu then
    local ok, gw, gh = pcall(function() return gpu.getResolution() end)
    if ok and gw then M.W, M.H = gw, gh end
end
local DEPTH = 8
if gpu then
    local okd, md = pcall(function() return gpu.maxDepth() end)
    if okd and md then
        DEPTH = md
        pcall(function()
            if md >= 8 then gpu.setDepth(8) else gpu.setDepth(md) end
        end)
    end
end
M.THEME = {
    canvas   = 0x05080d,   -- 接近纯黑，避免整屏发暗
    surface  = 0x141a24,   -- 卡片底
    panel    = 0x0d121a,
    border   = 0x33415c,   -- 卡片边框
    borderOn = 0x6ea8ff,   -- 选中的卡片边框
    text     = 0xffffff,
    muted    = 0x9fb0c8,
    accent   = 0x7fc4ff,
    selected = 0x1d3a5f,   -- 选中卡片底
    warn     = 0xfacc15,
    error    = 0xfb7185,
    ok       = 0x4ade80,
}
if DEPTH < 8 then
    M.THEME = {
        canvas   = 0,
        surface  = 8,
        panel    = 0,
        border   = 8,
        borderOn = 11,
        text     = 15,
        muted    = 7,
        accent   = 11,
        selected = 8,
        warn     = 14,
        error    = 12,
        ok       = 10,
    }
end

function M.color(role, fallback)
    if type(role) == "number" then return role end
    return M.THEME[role] or M.THEME[fallback or "text"]
end

local lastFg, lastBg
function M.useFg(role)
    if not gpu then return end
    local c = M.color(role, "text")
    if lastFg ~= c then
        pcall(gpu.setForeground, c)
        lastFg = c
    end
end
function M.useBg(role)
    if not gpu then return end
    local c = M.color(role, "canvas")
    if lastBg ~= c then
        pcall(gpu.setBackground, c)
        lastBg = c
    end
end
function M.resetColorCache()
    lastFg, lastBg = nil, nil
end

function M.fit(s, width)
    s = tostring(s or "")
    if width <= 0 then return "" end
    local ok, w = pcall(function() return unicode.wlen(s) end)
    if ok and w and w > width then
        local ok2, r = pcall(function() return unicode.wtrunc(s, width) end)
        if ok2 and r then return r end
        return s:sub(1, width)
    elseif not ok and #s > width then
        return s:sub(1, width)
    end
    return s
end
function M.ulen(s)
    s = tostring(s or "")
    local ok, n = pcall(function() return unicode.wlen(s) end)
    return (ok and n) or #s
end
function M.usub(str, a, b)
    str = tostring(str or "")
    local ok, r = pcall(function() return unicode.sub(str, a, b) end)
    return (ok and r) or str:sub(a, b)
end
function M.wrapText(text, width, maxLines)
    text = tostring(text or "")
    local out, cur = {}, ""
    if width <= 0 then return out end
    local n = M.ulen(text)
    for i2 = 1, n do
        local ch = M.usub(text, i2, i2)
        if ch == "\n" then
            out[#out + 1] = cur
            cur = ""
        else
            local try = cur .. ch
            if M.ulen(try) > width then
                out[#out + 1] = cur
                cur = ch
            else
                cur = try
            end
        end
        if maxLines and #out >= maxLines then return out end
    end
    if cur ~= "" and (not maxLines or #out < maxLines) then out[#out + 1] = cur end
    return out
end
function M.waitInput()
    while true do
        local e = { event.pull() }     -- 不带过滤器、不带超时：纯阻塞，最稳
        local name = e[1]
        if name == "key_down" then
            return "key_down", e[3], e[4]
        elseif name == "touch" then
            return "touch", e[3], e[4]
        end
    end
end
function M.padRight(s, width)
    s = tostring(s or "")
    local ok, w = pcall(function() return unicode.wlen(s) end)
    w = (ok and w) or #s
    local pad = width - w
    if pad < 1 then pad = 1 end
    return s .. string.rep(" ", pad)
end

-- 点击命中区:绘制层写入,输入层查询
local hits = {}
function M.clearHits()
    hits = {}
end
function M.addHit(h)
    hits[#hits + 1] = h
end
function M.hitAt(x, y)
    for _, h in ipairs(hits) do
        local y1 = h.y1 or h.y
        local y2 = h.y2 or h.y
        if y >= y1 and y <= y2 and x >= h.x1 and x <= h.x2 then
            return h.action
        end
    end
    return nil
end

function M.put(x, y, text, fgRole, bgRole)
    if y < 1 or y > M.H or x > M.W then return end
    term.setCursor(x, y)
    M.useFg(fgRole or "text")
    M.useBg(bgRole or "canvas")
    term.write(M.fit(text, M.W - x + 1))
end
function M.hook(x, y, text, action)
    M.addHit({ x1 = x, x2 = x + M.ulen(text) - 1, y = y, action = action })
end
function M.drawCard(x, y, w, h, t, isSel)
    local bg = isSel and "selected" or "surface"
    local bd = isSel and "borderOn" or "border"
    M.useBg(bg)
    M.useFg("text")
    for r = 0, h - 1 do
        term.setCursor(x, y + r)
        term.write(string.rep(" ", w))
    end
    M.useFg(bd)
    M.useBg(bg)
    term.setCursor(x, y)
    term.write("┌" .. string.rep("─", w - 2) .. "┐")
    for r = 1, h - 2 do
        term.setCursor(x, y + r); term.write("│")
        term.setCursor(x + w - 1, y + r); term.write("│")
    end
    term.setCursor(x, y + h - 1)
    term.write("└" .. string.rep("─", w - 2) .. "┘")
    local inner = w - 4
    M.put(x + 2, y + 1, t.name, isSel and "accent" or "text", bg)
    local descLines = M.wrapText(t.desc or "", inner, h - 3)
    for k, ln in ipairs(descLines) do
        M.put(x + 2, y + 1 + k, ln, "muted", bg)
    end
    return inner
end

return M
