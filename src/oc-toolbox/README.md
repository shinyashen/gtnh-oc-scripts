# oc-toolbox · 样板OC工具箱(分体改良版)

GTNH 中文维基《指南:样板OC工具箱》所引 gist 单文件脚本的**分体重构 + 功能增强版**:把常用的 AE2 样板操作(NAC 电路/神锻等离子/夸克/磁物质样板批量生成、样板合并、高炉转流体、保护气替换、压模改固化)打包成触屏/键盘卡片菜单,并把原独立的《指南:基于OC的无线电网监控》兰波顿 EU 监控合并为菜单工具。

## 来源与依据版本

- 维基教程:[指南:样板OC工具箱](https://gtnh.huijiwiki.com/wiki/%E6%8C%87%E5%8D%97:%E6%A0%B7%E6%9D%BFOC%E5%B7%A5%E5%85%B7%E7%AE%B1)(页内只有安装命令,无代码块;作者柳叶刀kk)
- 上游代码:[kAGuyAk gist 45f36eec](https://gist.github.com/kAGuyAk/45f36eeca31fb2fc536a000d5d9d3a80)(**未声明许可证,版权归作者**;`upstream/gistfile1.txt` 为 Actions 自动同步的最新副本)
- 本版依据:gist 修订 **`c69ad0e9`**(2026-11-14,即脚本内 `VERSION = "1115-62ddaa"`)
- 监控功能来自:[维基·指南:基于OC的无线电网监控](https://gtnh.huijiwiki.com/wiki/%E6%8C%87%E5%8D%97:%E5%9F%BA%E4%BA%8EOC%E7%9A%84%E6%97%A0%E7%BA%BF%E7%94%B5%E7%BD%91%E7%9B%91%E6%8E%A7) 页内脚本(= [Yecgaa1/xtxChino_GTNH_OC](https://github.com/Yecgaa1/xtxChino_GTNH_OC) 的 `fork/wireless-powerd.lua` + 6 行分辨率改动;`upstream/wireless-powerd.lua` 为其 Actions 同步副本,GPL-3.0)

## 部署结构(OpenOS)

| 磁盘路径 | 内容 |
|---|---|
| `/home/bin/toolbox` | 主入口:启动器 + 卡片菜单 + CLI(`toolbox` / `list` / `about` / `diag` / `<工具id> [参数]`) |
| `/home/lib/*.lua` | 公共库 ×4:`toolbox_ui`(绘制/命中) `toolbox_ctx`(GUI+CLI 交互) `ae2_iface`(接口/样板公共函数+槽位探测) `eu_fmt`(EU 格式化) |
| `/home/tools/*.lua` | 工具 ×7:`pattern-gen` `pattern-merge` `pattern-to-fluid` `shield-gas` `compression-fix` `wireless-eu-monitor` `_template`(模板,不进菜单) |

`/home/bin` 在 OpenOS 默认 PATH、`/home/lib` 在默认 require 路径(OpenOS `lib/package.lua` 实证),放好即用。工具按需加载:启动只读元数据,首次运行才 loadfile,之后缓存常驻(工具内部状态跨菜单连续)。

依赖:适配器紧贴 ME 接口(样板类工具;`fluid_interface` 优先,退回 `me_interface`);数据库升级仅在"改名写入"路径需要;监控需兰波顿超级电容库的适配器(`gt_machine`),OpenGlasses 眼镜可选(无则自动降级仅屏幕)。开机自启监控示例(`.shrc`):

```sh
/home/bin/toolbox wireless-eu-monitor
/home/bin/toolbox
```

## 与上游单文件版的差异

重构(行为不变):

1. **单文件 → 分体**:内嵌工具字符串(首次运行落盘 + 指纹自举机制)改为真实文件 + `/home/lib` 公共库;5 个工具内逐字相同的 AE2 辅助函数合并进 `ae2_iface.lua`(对拍 diff 确认逻辑零改动)。
2. **按需加载**:启动只读各工具元数据,进入时才加载,菜单/CLI 行为与上游一致。

功能增强:

3. **无线电网监控合并为菜单工具**(上游无电源/监控类功能,独立"监控"组):
   - Q 或 Ctrl+C 返回上层(菜单/shell),退出即回菜单无"按任意键"暂停;菜单挂机期间 `event.timer` 后台采样器持续积累 24h 窗口并刷新眼镜 HUD(数据连续性)。
   - 多 `gt_machine` 时列出组件供选择,记住到 `/home/tools/.monitor.cfg`;退出监控清空眼镜文字、恢复进入前分辨率。
   - **传感器读取失败不崩溃**(上游对 `getSensorInformation()[23]` 零容错,服务器重启后组件未就绪即 nil 崩溃):跳过采样、保留窗口、屏幕显示"读取失败"。
   - **分钟聚合持久化** `/home/tools/.eu_log`(≤1440 行 ≈29KB):每运行分钟记录绝对 EU 值,1h/1d 均值与耗尽时间重启即恢复(算法与原秒级窗口在无缺口时精确等价);5s/1m/5m 短窗口仍为秒级。
4. **接口样板槽位自适应**:GTNH 接口 9/18/27/36 槽四档,`ae2_iface.patternSlotCount` 递增探测并按接口地址缓存(上游全部硬编码 36)。
5. **通道样板检测 + 引用替换**(`pattern-gen`,2.9 新样板类型,只有输入无输出):
   - 类型判据:`getInterfacePattern` 返回 outputs 为空 + `isCraftable==false` + inputs≥1;再按 wiki 旧方案**写死内容**匹配——红板=5×32 改名光学贴片(`gregtech:gt.metaitem.03`)+**改名**光学电路基板×4(基板不带命名则整板不认),蓝板=5×32 原名光学贴片;写了其他内容的通道样板一律不认。红/蓝各只认扫描到的第一张。
   - 配方项按 `(name, damage, hasTag)` 三元组整组对齐——**同一物品的命名/未命名形态各自独立分组**(如未命名光学电路基板项不会被红板的命名基板吸收,保持原名写入),**统一整数倍 k 缩放**(引用×k = 内容×k;皮米=红×1+蓝×1,量子=红×2+蓝×2),对不上则保持原改名写入。皮米/量子配方里基板的注册 id 本就不同(`metaitem.01`/`metaitem.03:32728`),红板基板 id 与某条电路不同时该电路自然不替换,属预期行为。
   - 引用写入靠通道样板物品完整 NBT(`tag` 字段 gzip)无损透传给 `setInterfacePatternInput`,**无需数据库升级改名**(改名项被完全覆盖时跳过改名询问)。前提:config `allowItemStackNBTTags=true`。
   - 通道样板所在槽被排除出占位槽候选,批量写入永不覆写。
6. **框架切割液选择**(`pattern-gen`):NAC 纳米精度切割仓的框架切割各有可选切割液(数据 2.9 经中文维基在线 NEI 数据库核对),生成含框架的样板时询问(每项标注 单框架用量×框架数,Q 保持默认)。**2.9.1 起磁物质框架的八级净化水 500L 配方已删除**(CoreMod `ScriptNanochipRecipes` PR #2044),只剩维度偏移超流体一条路线,该项不再询问:

   | 框架 | 默认 | 可选 |
   |---|---|---|
   | 天体钨 | 六级净化水 250L | 五级净化水 250L |
   | 海珀珍 | 七级净化水 500L | 八级净化水 250L |
   | 磁物质 | 维度偏移超流体 100L（唯一路线,2.9.1 起不询问） | — |
7. **量子电路配方修正**:补上游缺失的 **288L `molten.radoxpoly`**(拉多X聚合物;英文维基 NAC 页 Quantum Circuit 配方确认,gist `c69ad0e9` 漏项)。
8. **皮米电路配方修正**:上游把"命名的光学电路基板"的分册号写错——`gt.metaitem.01:32728` 实为**锁升级**(Lock Upgrade,`IDMetaItem01.Upgrade_Lock(728)`+32000),光学电路基板在 `gt.metaitem.03:32728`(`IDMetaItem03.Circuit_Board_Optical(728)`);已改为 `.03`(量子电路原本就正确)。此错同时导致上游走改名路径时写出"改名锁升级"、通道替换因基板三元组不匹配而保守拒绝——修正后皮米可正常引用红板。

## 运行时文件(不入库)

`/home/tools/.monitor.cfg`(监控组件记忆)、`/home/tools/.eu_log`(EU 分钟历史)。
