# wireless-eu-monitor · 无线电网(Lapotronic)EU 功率监控

每秒采样无线电网 EU 总量,屏幕输出 5s/1m/5m/1h/1d 均值,并经 OpenGlasses 眼镜 HUD 显示 5m/1h 均值、总储量、按小时均值外推的耗尽时间(<1h 红字报警)。数据窗口 24h。

- 教程:[GTNH 中文维基·指南:基于OC的无线电网监控](https://gtnh.huijiwiki.com/wiki/%E6%8C%87%E5%8D%97:%E5%9F%BA%E4%BA%8EOC%E7%9A%84%E6%97%A0%E7%BA%BF%E7%94%B5%E7%BD%91%E7%9B%91%E6%8E%A7)(页内代码见 `wiki/`)
- 上游脚本:[Yecgaa1/xtxChino_GTNH_OC](https://github.com/Yecgaa1/xtxChino_GTNH_OC) 的 `fork/wireless-powerd.lua`(`upstream/wireless-powerd.lua` 为 Actions 自动同步的最新副本)
- 部署版与上游差异极小(忽略 CRLF/空白后仅 6 行:屏幕分辨率 80×14→60×20 等本地显示调整),逻辑与上游一致

## 依赖

- 显卡 + 屏幕(60×20)、AR 眼镜组件(OpenGlasses)、**一台兰波顿超级电容库的适配器**(提供 `gt_machine` 组件)。
- 数据源:`gt_machine.getSensorInformation()[23]` = 无线电网 EU 总量;**GTNH 2.7.0 之前是 `[19]`**。
- 兰波顿无线电网每 6000 ticks(5 分钟)结算一次上传,故均值取 5m/1h 以避开上传峰;耗尽时间基于小时均值计算。

## 背景机制

无线 EU 网络由兰波顿超级电容库开启,管理指令 `/gt global_energy_set|add [玩家名] [EU量]`;电容库把超过阈值的电量在结算时上传到无线网络。详见 [维基·兰波顿超级电容库](https://gtnh.huijiwiki.com/wiki/%E5%85%B0%E6%B3%A2%E9%A1%BF%E8%B6%85%E7%BA%A7%E7%94%B5%E5%AE%B9%E5%BA%93)。
