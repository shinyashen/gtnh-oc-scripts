-- GTNH 上古末影龙农场 · 龙蛋采集机器人 v3（锁定方向 · 无限采集）
-- 位置：龙蛋旁同一高度。装备槽：一把剑。
-- 库存 1 号槽：一个龙蛋样本（compareTo 确认面前是龙蛋）。
-- 阶段1：四方向转身扫描，比对到龙蛋即锁定该朝向（蛋未生成时持续轮询）。
-- 阶段2：朝向永不再变——蛋生成 → 潜行左键破坏 → 掉落物走你的吸取途径 → 等下一颗。
-- 红线：挥剑第二参数 true = 潜行。GTNH 龙蛋必须潜行左键采集，普通左键会让它瞬移。

local robot = require("robot")

local EGG_SLOT = 1
local POLL = 10

robot.select(EGG_SLOT)

-- 阶段1：转身扫描直到比对到龙蛋
while not robot.compare(true) do
  robot.turnRight()
  os.sleep(1)
end

-- 阶段2：朝向已正对龙蛋，无限采集
while true do
  if robot.compare(true) then
    robot.swing(nil, true)
  end
  os.sleep(POLL)
end
