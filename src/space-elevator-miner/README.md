# space-elevator-miner · 太空电梯矿机/钻机参数自动管理(2.9.0 深度改版)

按请求器(level_maintainer)设定的目标量,周期读取 ME 网络库存,自动换矿机配方无人机、写矿机(distance/step/parallel 等)与钻机(planetType/gasType/parallel/batch)参数,并读回验证。目标值仅作比值不超量停机;参数 +100000(如 108100)可强制超量停止。

- 原始教程:[GTNH 中文维基·指南:基于OC的太空电梯智能管理](https://gtnh.huijiwiki.com/wiki/%E6%8C%87%E5%8D%97:%E5%9F%BA%E4%BA%8EOC%E7%9A%84%E5%A4%AA%E7%A9%BA%E7%94%B5%E6%A2%AF%E6%99%BA%E8%83%BD%E7%AE%A1%E7%90%86)(脚本仅内嵌在 wiki 页,**无上游仓库**;`wiki/` 为 Actions 搬运的页内代码块,`notes/` 为当时探测的组件清单与机器参数笔记)
- 本版 `miner.lua` = wiki 老脚本(284 版)在 GTNH 2.8.4→2.9.0 后的深度改版:**v2.3-290适配 r14 钻机多线程版**(md5 `d9179661…`)

## 2.9.0 适配要点(与 wiki 版不兼容处)

1. AE2 流体读取组件是 **`me_interface`**(wiki 老脚本绑的 `fluid_interface` 在 290 已不存在)。
2. `gt_machine` 的 `setParameters/getParameters` 表式 API 被移除,改为按字符串键的 **`setParameter(key, value)`**;实测键名:
   - 钻机(T2/T3 泵机):`batch`、`recipeN.parallel`、`recipeN.planetType`、`recipeN.gasType`(N=0..线程数-1)
   - 矿机:`distance`、`cycle`、`cycleDistance`、`step`、`parallel`、`range`
3. r14 支持多线程泵机:T2/UEV 4 线程、T3/OpV 4 线程 64 并行,`resolveKeys` 按 `recipeN.` 前缀归组逐线程写入并读回验证;T1 单线程行为与老版兼容。
4. 全部线程设同一流体 = 多线程叠加产出;建议配 ME 输出仓,避免多线程争同一锁定流体仓。

## 使用要点

- 30s 检测间隔、`pumpBatch=nil`(不自动设批处理)、`allowRandomMine=true`(目标等级不足时随机填充)。
- ME 接口(二合一)必须紧贴 OC 线缆/适配器才会被扫描到;请求器第二列填缓存目标量,第三列机器参数格式:矿石 = 1000×无人机等级+距离,钻机 = 1000×星球类型+气体类型(如 8100、7004)。
- 服务器运行中替换磁盘文件时,OC 内存里仍是旧代码,重启(或区块卸载重载)后生效。
