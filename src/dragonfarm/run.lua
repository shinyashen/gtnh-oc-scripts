-- GTNH 上古末影龙农场 · 复活石触发机器人（最终版）
-- 位置：复活石正上方一格，向下右键触发仪式。
-- 红线：装备槽必须保持为空（空手右键）。
-- 节奏：触发成功 → 冷却 3 秒（此窗口内移位器必须把机器人搬离爆心）→ 继续循环。

local component = require("component")

local COOLDOWN = 3

while true do
  local ok, reason = component.robot.use(0, 0)
  if ok and reason == "block_activated" then
    os.sleep(COOLDOWN)
  end
end
