# nuclear-cooler · GTNH-NuclearCooler 强冷核电(上游部署快照)

IC2 核电仓自动换料 + 过热保护 + 电量锁存红石控制,多堆并发(协程)。上游项目:[ljhljll/GTNH-NuclearCooler](https://github.com/ljhljll/GTNH-NuclearCooler)。

- `upstream/` 为 Actions 自动同步的上游整仓快照(不含 `.git`),可随时 diff 对照;
- 组根目录是**当前实际部署的文件**,其中我们自己的配置:

## 部署文件结构

| 文件 | 说明 |
|---|---|
| `GTNH-NuclearCooler/justStart.lua` | 主入口(新套件,多堆协程) |
| `GTNH-NuclearCooler/config.lua` | **我们的配置**:4 种配方方案(`slyb` 铀 / `mox` / `yghhw` 钍四联+荧石单元 / `jfy` 激发铀),实际启用 `jf堆1-4` 走 `jfy` 方案;`energyLatchRedstone`/`globalRedstone` 为红石端口地址 |
| `GTNH-NuclearCooler/` 其余 | `action.lua` 换料动作、`coolantcellThread.lua` 电量锁存协程、`database.lua` 运行状态 |
| `index.lua` + `config.json` | 旧版单堆入口(legacy,保留备查) |
| `JSON.lua` | JSON 解析库(旧入口依赖) |

## 运行要点

- 全局红石开关(地址 `globalRedstone`)拉高才运行,拉低 2s 后退出并停堆。
- 每堆按方案周期检测冷却单元耐久(dmg 阈值)与燃料棒枯竭(`changeName`),停堆→取出→换新→重启。
- `energy=nil` 的堆参与电量控制:电量锁存端口无信号时停堆待命,缺电时才开启。
- 启动后选择模式:0=从配置校验料量后启动,1=直接启动。
