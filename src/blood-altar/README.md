# blood-altar · 血魔法祭坛自动化 & 宝珠常驻(上游改良版)

血祭坛全自动:合成投料/产物输出、宝珠自动充能与常驻、苦难之井 GTM 加速器与祭坛 GTM 加速器分开启停(合成/充能才加速,防苦难之井 LP 干完)。

- 教程与原版/改良版脚本:[GTNH 中文维基·指南:血魔法祭坛自动化](https://gtnh.huijiwiki.com/wiki/%E6%8C%87%E5%8D%97:%E8%A1%80%E9%AD%94%E6%B3%95%E7%A5%AD%E5%9D%9B%E8%87%AA%E5%8A%A8%E5%8C%96)(页内代码见 `wiki/`)
- 上游脚本:[Yecgaa1/xtxChino_GTNH_OC](https://github.com/Yecgaa1/xtxChino_GTNH_OC) 的 `blood.lua`(`upstream/blood.lua` 为 Actions 自动同步的最新副本)

## 接线要求

转运器五向:up 宝珠槽(推荐微型箱)、west 输入(抽屉/JABBA 桶,`inputSlot=2`)、east 输出(推荐 ME 接口)、north 祭坛(血魔法祭坛 + 适配器/MFU)。`altarAddress` 填祭坛世界加速器地址——查适配器或 MFU 内部 `oc:adapter.block-data-address`。

## 相对上游 blood.lua 的改动(diff 约 50 行)

- **`idleAccelerate` 闲时开关**(上游没有):宝珠常驻(祭坛上只有宝珠、无合成)时是否开加速器,默认 false;改完需重跑脚本。
- **armok(阿蒙克)分支重构**:上游 `isArmokOrb=true` 时直接按 `2147483647` 处理最大 LP,且阿蒙克宝珠绑定后 `orbTier` 语义会让常态加速器误判;本版保持 `isArmokOrb=false`,统一按 `item.orbTier == nil`(未绑定宝珠/合成材料)判定加速,阿蒙克宝珠绑定后可正常常驻充能不误加速。

## 脚本行为速览

1. `checkAcceleration()`:有合成材料或未绑定宝珠 → 两路加速器全开;纯宝珠常驻时看 `idleAccelerate`。
2. `checkSoulNetworkEssence()`:宝珠 LP 低于 `minimumLPGradient × 最大LP` 时把宝珠转运到祭坛充能,充满后关加速器。
3. 合成流程:输入容器有料 → 若祭坛上是宝珠先 `refundOrb()` 回宝珠箱 → 投料 → 产物 label 变化即 `setOutput()` 到 ME 接口。
