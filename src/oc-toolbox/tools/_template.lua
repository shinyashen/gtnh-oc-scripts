-- 工具模板:复制一份改 id/name/group/desc 和 run() 就是一个新工具(_ 开头文件不进菜单)。
-- 公共函数用 require 引分体版公共库,例如:
--   local lib = require("ae2_iface")   -- AE2 接口/样板公共函数
--   local ui  = require("toolbox_ui")  -- 屏幕绘制
--   local fmt = require("eu_fmt")      -- EU 数值格式化

local M = {
    id = "my-tool",              -- 命令用的短名，和文件名一致最省事
    name = "我的工具",            -- 菜单里显示的名字（中文短一点，12 格内好看）
    group = "其他",               -- 菜单分组，同一组会排在一起
    order = 100,                  -- 组内排序，小的在前（随意）
    desc = "一句话说明这是干嘛的",   -- 菜单里跟在名字后面的说明
}
function M.check(ctx)
    return true, "环境正常"
end
function M.run(ctx, args)
    args = args or {}
    ctx.clear()
    ctx.title("我的工具")
    ctx.write("这里是工具的输出")
    ctx.write("")
    local v = ctx.ask("输入点什么（直接回车跳过）> ", "默认值")
    ctx.write("你给了：" .. tostring(v))
    ctx.write("")
    for i2 = 1, 3 do
        ctx.write(string.format("  第 %d 步……", i2))
        os.sleep(0)
    end
    ctx.write("")
    ctx.pause("做完了。")
    return true
end
return M
