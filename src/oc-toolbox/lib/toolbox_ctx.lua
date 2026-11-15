-- toolbox_ctx:传给工具的 ctx 交互接口(GUI 全屏 select/prompt/confirm/cardSelect + CLI 版)
-- 拆分自上游单文件版《样板OC工具箱》主程序,行为保持一致。
local term = require("term")
local event = require("event")
local component = require("component")
local ui = require("toolbox_ui")

local M = {}

function M.makeCtx(opts)
    opts = opts or {}
    local ctx
    local function resetScreen()
        term.setCursorBlink(false)
        term.clear()
        term.setCursor(1, 1)
        ui.resetColorCache()
        ui.useBg("canvas")
        ui.clearHits()
    end
    local function doSelect(items, o)
        o = o or {}
        local sel = tonumber(o.default) or 1
        local head = o.title or "请选择"
        local foot = o.footer or "点一下选中   ↑↓ 移动   Enter 确定   Q 返回（别按 Esc，那是游戏菜单）"
        local top = o.top or 3
        local bottom = ui.H - 2
        while true do
            if ctx then ctx.hadSelect = true end
            resetScreen()
            ui.put(1, 1, "  " .. head, "accent", "surface")
            ui.put(1, 2, string.rep("-", ui.W), "border", "canvas")
            local y = top
            for i2, it in ipairs(items) do
                if y + 1 > bottom then break end
                local isSel = (i2 == sel)
                local bg = isSel and "selected" or "canvas"
                term.setCursor(1, y)
                ui.useBg(bg)
                pcall(function() term.clearLine() end)
                local mark = isSel and "> " or "  "
                ui.put(1, y, mark .. tostring(it.label or ""), isSel and "accent" or "text", bg)
                if it.desc and tostring(it.desc) ~= "" then
                    local d = tostring(it.desc)
                    local dx = math.floor(ui.W / 2)
                    if dx > ui.ulen(mark .. tostring(it.label or "")) + 2 then
                        ui.put(dx, y, d, "muted", bg)
                    end
                end
                term.setCursor(1, y + 1)
                ui.useBg(bg)
                pcall(function() term.clearLine() end)
                ui.addHit({
                    x1 = 1, x2 = ui.W, y1 = y, y2 = y + 1,
                    action = { kind = "pick", idx = i2 },
                })
                y = y + 2
            end
            ui.put(1, ui.H - 1, string.rep("-", ui.W), "border", "canvas")
            local btxt = "[ 返回 ]"
            ui.put(1, ui.H, btxt, "muted", "surface")
            ui.addHit({ x1 = 1, x2 = ui.ulen(btxt), y1 = ui.H, y2 = ui.H,
                        action = { kind = "back" } })
            ui.put(ui.ulen(btxt) + 2, ui.H, foot, "muted", "canvas")
            term.setCursor(1, ui.H)
            local ev, a, b = ui.waitInput()
            if ev == "touch" then
                local act = ui.hitAt(a, b)
                if act and act.kind == "pick" then
                    local it = items[act.idx]
                    if it then return it.value, it end
                elseif act and act.kind == "back" then
                    return nil
                end
            elseif ev == "key_down" then
                local ch, code = a, b
                if code == 200 then
                    sel = math.max(1, sel - 1)
                elseif code == 208 then
                    sel = math.min(#items, sel + 1)
                elseif code == 28 then
                    local it = items[sel]
                    if it then return it.value, it end
                elseif ch == 113 or ch == 81 then
                    return nil
                elseif ch and ch >= 49 and ch <= 57 then
                    local n2 = tonumber(string.char(ch))
                    if n2 and items[n2] then return items[n2].value, items[n2] end
                end
            end
        end
    end
    local function doPrompt(question, default, hint)
        local buf = ""
        while true do
            resetScreen()
            ui.clearHits()
            ui.put(1, 1, "  " .. tostring(question), "accent", "surface")
            ui.put(1, 2, string.rep("-", ui.W), "border", "canvas")
            local shown = (buf ~= "") and buf or "（还没输入，直接回车就用默认）"
            ui.put(1, 4, "  当前：" .. shown, "text", "canvas")
            ui.put(1, 5, "  回车 = 用 " .. (default ~= nil and ("「" .. tostring(default) .. "」") or "空"),
                "muted", "canvas")
            ui.put(1, ui.H - 1, string.rep("-", ui.W), "border", "canvas")
            local bx = 1
            local function btn(label, act, fg)
                local txt = "[ " .. label .. " ]"
                ui.put(bx, ui.H, txt, fg or "accent", "surface")
                ui.addHit({ x1 = bx, x2 = bx + ui.ulen(txt) - 1, y1 = ui.H, y2 = ui.H, action = act })
                bx = bx + ui.ulen(txt) + 1
            end
            btn("确定", { kind = "ok" })
            btn("取消", { kind = "cancel" }, "muted")
            ui.put(bx + 1, ui.H, "  打字输入，Enter 或点「确定」提交", "muted", "canvas")
            term.setCursorBlink(true)
            term.setCursor(1 + ui.ulen("  当前：") + ui.ulen(shown) + 1, 4)
            local ev, a, b = ui.waitInput()
            if ev == "touch" then
                local act = ui.hitAt(a, b)
                if act then
                    term.setCursorBlink(false)
                    if act.kind == "ok" then
                        if buf ~= "" then return buf end
                        return default
                    elseif act.kind == "cancel" then
                        return nil
                    end
                end
            elseif ev == "key_down" then
                local ch, code = a, b
                if code == 28 then
                    term.setCursorBlink(false)
                    if buf ~= "" then return buf end
                    return default
                elseif code == 14 then
                    if #buf > 0 then buf = buf:sub(1, #buf - 1) end
                elseif ch and ch >= 32 and ch < 127 then
                    if #buf < 40 then buf = buf .. string.char(ch) end
                end
            end
        end
    end
    local function doConfirm(question, yesHint, noHint)
        local v = doSelect({
            { label = yesHint or "确定", value = true },
            { label = noHint or "取消", value = false },
        }, {
            title = question,
            default = 1,
            footer = "点按钮选择   ↑↓ 移动   Enter 确定   Q = 取消",
        })
        return v == true
    end
    local function doCardSelect(items, o)
        o = o or {}
        local sel = 1
        local head = o.title or "请选择"
        local cw = math.min(60, ui.W - 6)
        local ch = 4
        while true do
            resetScreen()
            ui.clearHits()
            ui.put(1, 1, "  " .. head, "accent", "surface")
            ui.put(1, 2, string.rep("─", ui.W), "border", "canvas")
            for i, it in ipairs(items) do
                local y = 4 + (i - 1) * (ch + 1)
                if y + ch - 1 <= ui.H - 2 then
                    ui.drawCard(3, y, cw, ch,
                        { name = tostring(it.label or ""), desc = tostring(it.desc or "") }, i == sel)
                    ui.addHit({
                        x1 = 3, x2 = 3 + cw - 1, y1 = y, y2 = y + ch - 1,
                        action = { kind = "pick", idx = i },
                    })
                end
            end
            ui.put(1, ui.H - 1, string.rep("─", ui.W), "border", "canvas")
            local btxt = "[ 返回 ]"
            ui.put(1, ui.H, btxt, "muted", "surface")
            ui.addHit({ x1 = 1, x2 = ui.ulen(btxt), y1 = ui.H, y2 = ui.H, action = { kind = "back" } })
            ui.put(ui.ulen(btxt) + 2, ui.H, "↑↓ 选择   Enter 确定   Q 返回", "muted", "canvas")
            local ev, a, b = ui.waitInput()
            if ev == "touch" then
                local act = ui.hitAt(a, b)
                if act and act.kind == "pick" then
                    local it = items[act.idx]
                    if it then return it.value or it.label, it end
                elseif act and act.kind == "back" then
                    return nil
                end
            elseif ev == "key_down" then
                local ch2, code = a, b
                if code == 200 then
                    sel = math.max(1, sel - 1)
                elseif code == 208 then
                    sel = math.min(#items, sel + 1)
                elseif code == 28 then
                    local it = items[sel]
                    if it then return it.value or it.label, it end
                elseif ch2 == 113 or ch2 == 81 then
                    return nil
                end
            end
        end
    end
    ctx = {
        term = term,
        event = event,
        component = component,
        width = ui.W,
        height = ui.H,
        clear = function()
            resetScreen()
        end,
        write = function(s2)
            ui.useFg("text")
            term.write(ui.fit(s2, ui.W))
            term.write("\n")
        end,
        writeRaw = function(s2)
            term.write(ui.fit(s2, ui.W))
        end,
        ask = function(prompt, default)
            if prompt then term.write(ui.fit(prompt, ui.W)) end
            local ok, line2 = pcall(function() return term.read() end)
            if not ok or line2 == nil or line2 == "" then return default end
            return line2
        end,
        pause = function(msg)
            if msg then term.write(ui.fit(msg, ui.W)) end
            term.write(ui.fit("按任意键继续……", ui.W))
            ui.waitInput()
        end,
        title = function(s2)
            local x, y = term.getCursor()
            ui.put(1, 1, "  " .. tostring(s2), "accent", "surface")
            term.setCursor(x, y)
        end,
        select = doSelect,
        prompt = doPrompt,
        confirm = doConfirm,
        cardSelect = doCardSelect,
        hr = function(y)
            ui.put(1, y, string.rep("-", ui.W), "border", "canvas")
        end,
        line = function(x, y, s2, fgRole, bgRole)
            ui.put(x or 1, y, s2, fgRole, bgRole)
        end,
    }
    return ctx
end

function M.cliCtx()
    return {
        term = term,
        event = event,
        component = component,
        width = 1000,
        height = 1000,
        clear = function() end,
        write = function(s) print(tostring(s)) end,
        writeRaw = function(s) io.write(tostring(s)) end,
        ask = function(prompt, default)
            if prompt then io.write(tostring(prompt)) end
            local line = io.read()
            if line == nil or line == "" then return default end
            return line
        end,
        pause = function(msg)
            if msg then print(tostring(msg)) end
        end,
        title = function(s) print(tostring(s)) end,
    }
end

return M
