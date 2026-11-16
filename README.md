# gtnh-oc-scripts

个人在 GT New Horizons 2.9.0 使用/借鉴的 OpenComputers 脚本存档,仅作脚本收纳与出处对照,不含任何部署信息。

`src/<组名>/` 每个文件夹解决一类问题,组内包含:

- **脚本文件**(当前使用的版本);
- **README.md**:功能说明、来源(wiki / 上游仓库)、与上游的差异;
- 有上游仓库的组另含 **`upstream/`**:GitHub Actions 自动同步的上游最新副本;
- 脚本出自 wiki 页内代码的组另含 **`wiki/`**:Actions 从 [GTNH 中文维基](https://gtnh.huijiwiki.com) 页面搬运的代码块(带页面版本记录 `revision.json`)。

## 组索引

| 组 | 简介 | 来源 |
|---|---|---|
| [dragonfarm](src/dragonfarm/) | 上古末影龙复活仪式触发 + 龙蛋采集(两台机器人) | **原创** |
| [blood-altar](src/blood-altar/) | 血魔法祭坛自动化 & 宝珠常驻 & 苦难之井加速器控制 | [维基·指南:血魔法祭坛自动化](https://gtnh.huijiwiki.com/wiki/%E6%8C%87%E5%8D%97:%E8%A1%80%E9%AD%94%E6%B3%95%E7%A5%AD%E5%9D%9B%E8%87%AA%E5%8A%A8%E5%8C%96) + [Yecgaa1/xtxChino_GTNH_OC](https://github.com/Yecgaa1/xtxChino_GTNH_OC) 改良 |
| [oc-toolbox](src/oc-toolbox/) | 样板OC工具箱分体改良版(AE2 样板批量生成/合并/改写 + 通道样板引用 + 兰波顿 EU 监控合并) | [维基·指南:样板OC工具箱](https://gtnh.huijiwiki.com/wiki/%E6%8C%87%E5%8D%97:%E6%A0%B7%E6%9D%BFOC%E5%B7%A5%E5%85%B7%E7%AE%B1)所引 [kAGuyAk gist 45f36eec](https://gist.github.com/kAGuyAk/45f36eeca31fb2fc536a000d5d9d3a80) 深度改良;监控部分源自[维基·无线电网监控](https://gtnh.huijiwiki.com/wiki/%E6%8C%87%E5%8D%97:%E5%9F%BA%E4%BA%8EOC%E7%9A%84%E6%97%A0%E7%BA%BF%E7%94%B5%E7%BD%91%E7%9B%91%E6%8E%A7)(已并入本组,原组删除) |
| [space-elevator-miner](src/space-elevator-miner/) | 太空电梯矿机/钻机参数自动管理(2.9.0 适配 r14) | [维基·指南:基于OC的太空电梯智能管理](https://gtnh.huijiwiki.com/wiki/%E6%8C%87%E5%8D%97:%E5%9F%BA%E4%BA%8EOC%E7%9A%84%E5%A4%AA%E7%A9%BA%E7%94%B5%E6%A2%AF%E6%99%BA%E8%83%BD%E7%AE%A1%E7%90%86) 页内脚本深度改版 |
| [nuclear-cooler](src/nuclear-cooler/) | IC2 强冷核电自动换料/过热保护(多堆协程) | [ljhljll/GTNH-NuclearCooler](https://github.com/ljhljll/GTNH-NuclearCooler) 部署快照 + 自有配置 |
| [blackhole-compressor](src/blackhole-compressor/) | 亚稳态黑洞遏制场自动化(种子/坍缩器/时空信号) | [维基·指南:亚稳态黑洞遏制场自动化](https://gtnh.huijiwiki.com/wiki/%E4%BA%9A%E7%A8%B3%E6%80%81%E9%BB%91%E6%B4%9E%E9%81%8F%E5%88%B6%E5%9C%BA%E8%87%AA%E5%8A%A8%E7%BB%B4%E6%8C%81%E6%95%99%E7%A8%8B) 页内脚本深度改良 |

## 镜像机制

`.github/workflows/mirror-upstream.yml` 每周一北京时间 20:00(UTC 周一 12:00,亦可手动触发)自动:

1. 拉取 `Yecgaa1/xtxChino_GTNH_OC` 的 `blood.lua` 与 `fork/wireless-powerd.lua`(监控上游,已并入 oc-toolbox 组)到对应 `upstream/`;
2. 拉取 [kAGuyAk gist 45f36eec](https://gist.github.com/kAGuyAk/45f36eeca31fb2fc536a000d5d9d3a80) 最新修订 raw 到 `src/oc-toolbox/upstream/`(commit message 记录 gist 修订号);
3. 整仓快照 `ljhljll/GTNH-NuclearCooler`(不含 `.git`)到 `src/nuclear-cooler/upstream/`;
4. 运行 `scripts/wiki_sync.py`:调灰机 wiki 的 MediaWiki API,把三个维基教程页的 `<syntaxhighlight lang="lua">` 代码块搬运到对应组 `wiki/`,并记录页面 `revid`(幂等,页面没改不重复;遇 Cloudflare 人机验证自动跳过该页,不影响其余同步);
5. 有变更时以 `github-actions[bot]` 身份提交(commit message 记录上游 commit sha)。

> 原 `wireless-eu-monitor` 组已并入 [oc-toolbox](src/oc-toolbox/)(作为其菜单工具),2026-11-16 删除;监控上游 `fork/wireless-powerd.lua` 的出处链接保留在 oc-toolbox 组 README。

原创组没有 `upstream/` 与 `wiki/`。

## 授权

见 [NOTICE.md](NOTICE.md) 与 [LICENSE](LICENSE)(GPL-3.0)。简述:原创脚本 GPL-3.0;衍生脚本随上游 GPL-3.0;维基搬运内容遵循其"署名-相同方式共享"协议;NuclearCooler 快照与 oc-toolbox 上游 gist 均未声明许可证,仅作出处指向,版权归其作者。
