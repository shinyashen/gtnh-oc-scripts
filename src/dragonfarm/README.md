# dragonfarm · 上古末影龙农场(OC 机器人,原创)

自动化上古末影龙复活仪式与龙蛋采集。**两份脚本均为原创**(API 语义经源码+字节码破案后精简定稿),无上游、无 wiki 出处。

- `run.lua` 复活仪式触发:机器人站**复活石正上方一格**,`component.robot.use(0, 0)` **向下右键**触发仪式,成功(`block_activated`)后冷却 3 秒循环。每轮消耗:4 怪兽灵魂 + 4 充能龙块 + 4 钻石块 + 1 复活石。
- `egg.lua` 龙蛋采集 v3:1 号槽放一个龙蛋样本,四方向转身 `robot.compare(true)` 锁定龙蛋朝向后**永不转向**,每 10s 轮询采集。

## 使用红线

- 触发机**装备槽必须保持为空**(空手右键)。
- 触发成功后 **3 秒内**移位器(TT Transvector Dislocator,绑定范围 16、红石脉冲、10t 冷却)必须把机器人搬离爆心——仪式结束会在石上方一格产生半径 10 的破坏性爆炸。
- 龙蛋必须**潜行左键** `robot.swing(nil, true)`,普通左键会让龙蛋瞬移。
- 不要让采蛋机的对角射线反复打祭坛萤石角(剑几下就敲碎)。
- 两台机器人开机自启未配 `autorun.lua`,重启后需手动运行。

## 关键坑(破案结论,勿再用直觉写)

- OC ROM 封装库把 facing 焊死为 `sides.front`:`robot.use(side)` 实际是 `component.robot.use(sides.front, side, …)`,**第二个参数只是命中面**;`robot.use(sides.bottom)` 点的是前方不是下方。绕过封装直调组件:`component.robot.use(s, s)`。
- `checkSideForAction` 只接受 0(down)/1(up)/3(front),传 2/4/5 直接抛 "unsupported side"。
