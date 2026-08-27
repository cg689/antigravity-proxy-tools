# Antigravity 免 TUN 代理 · 日常验证与更新维护手册

> 适用环境：本机（Windows，Antigravity 2.10.0 x64，2026-08-26 起实测兼容）
> 方案：antigravity-proxy v2.2（version.dll 劫持，进程级代理，免 TUN、免管理员）
> 整理日期：2026-08-22 ｜ 最近更新：2026-08-26（脚本升级为自愈版 v3.0）

---

## 一、这套方案是怎么工作的（30 秒版）

```
Antigravity 及其子进程  →  version.dll（安装目录里的劫持文件）
                       →  127.0.0.1:本地端口
                       →  你正在运行的代理软件（v2rayN / Clash Verge / Mesl 三选一）
                       →  出口节点
```

**关键认知：**
- TUN 模式、系统代理都**不需要开**，代理软件只要**在后台运行**即可
- ~~换代理软件 = 手动改 config.json~~ → **有校准脚本**（2026-08-22 起）：换软件后双击「切换代理后点我」即可自动改配置，见「二·五、手动切换」

---

## 二、三个代理软件端口速查表（本机实测）

| 代理软件 | 安装位置 | 配置里该填的端口 | 端口类型 | 端口配置文件位置（自查用） |
|---|---|---|---|---|
| **Clash Verge** | `D:\Software\Clash Verge` | **7897** | mixed（socks5/http 通用） | `%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\verge.yaml` → `verge_mixed_port` |
| **v2rayN** | `D:\Software\v2rayN-windows-64-desktop` | **10808** | socks5 | `guiConfigs\guiNConfig.json` → `inbound.LocalPort` |
| **Mesl**（当前配置） | `D:\Software\Mesl` | **7688** | **http**（不是 socks5！config.json 里 type 要填 `"http"`） | ⚠️ 以实测为准：runtime.yaml 里写的 7893 并未实际监听，真实端口是 7688；实测方法见下方 |

> ⚠️ 以上端口以**实测监听**为准。如果你在某个软件里改过端口设置，以软件界面显示为准，并同步改 config.json。

> 🔥 **2026-08-22 实测教训**：Mesl 配置文件里写的端口（7893）和实际监听的端口（7688）不一致，照配置文件填会导致"目标机器积极拒绝"。**切换软件时必须先验证端口真的在听、且能通 Google，再改 config.json**。

### 如何实测某个软件的真实代理端口（以 Mesl 为例）

```powershell
# 1. 找到代理核心的进程 PID（Mesl 的核心是 mihomo，v2rayN 7.x 的核心是 sing-box）
Get-Process mihomo
# 2. 看它在听哪些端口（把 <PID> 换成上一步看到的数字）
Get-NetTCPConnection -State Listen -OwningProcess <PID>
# 3. 逐个端口实测，能通百度的就是代理入站（http:// 和 socks5:// 两种前缀都试）
curl.exe -x http://127.0.0.1:7688 -s -o NUL -w "%{http_code}" https://www.baidu.com/
# 返回 200 = 端口可用；再验证能否通 Google：
curl.exe -x http://127.0.0.1:7688 -s -o NUL -w "%{http_code}" http://www.gstatic.com/generate_204
# 返回 204 = 节点能通 Google，Antigravity 就能用；返回 000 = 节点死了，换节点
```

### 切换代理软件的操作（2 分钟，顺序不能反）

0. **先验证目标软件的端口能用**（2026-08-22 踩坑后新增）：
   ```powershell
   Test-NetConnection 127.0.0.1 -Port 目标端口
   curl.exe -x http://127.0.0.1:目标端口 -s -o NUL -w "%{http_code}" http://www.gstatic.com/generate_204
   ```
   第一个 True、第二个返回 204，才能继续。（v2rayN 是 socks5，curl 的 -x 要写 `socks5://127.0.0.1:10808`）
1. 用记事本打开：
   ```
   C:\Users\Administrator\AppData\Local\Programs\antigravity\config.json
   ```
2. 找到这段，把 `port` 改成上表对应值，**注意 type 也要跟着改**（Mesl 是 `"http"`，其余两个是 `"socks5"`）：
   ```json
   "proxy": {
     "port": 7688,
     "type": "http",
     "host": "127.0.0.1"
   }
   ```
3. 保存，**完全退出 Antigravity 再重新打开**（托盘里也要退干净）

---

## 二·五、手动切换（已部署 v2，日常首选）

> 2026-08-22 晚调整：~~后台每 2 分钟自动检测~~ → 按你的要求改为**纯手动触发**，系统里没有任何驻留任务。
> 2026-08-22 v2 升级：脚本增加**重试机制**（3 轮 × 间隔 5 秒），解决切换代理软件后端口还没起来就检测导致误报 NO-PROXY 的问题。

**你的日常操作**（换代理软件后，共两步）：

1. **双击脚本**：`E:\文档\Antigravity管理\切换代理后点我（校准Antigravity）.cmd`
   - 脚本按优先级（Clash Verge 7897 → Mesl 7688 → v2rayN 10808）逐个实测：端口在听 **且** 能通 Google（curl 实测返回 204）
   - **如果第一轮三个端口全没通过，会自动等 5 秒重试**（最多 3 轮），解决刚切完代理软件端口还没起来的情况
   - 窗口会**实时显示**每个端口的检测过程（端口是否在听 → Google 是否可达）
   - 第一个通过的 = 当前生效代理，自动改写 config.json 的 port 和 type
   - 窗口最终显示结果：`OK` / `SWITCHED` = 成功；`NO-PROXY` = 三轮重试后仍不通（先检查软件和节点）
2. **重启 Antigravity**（完全退出再打开），生效

> **如果你刚切完代理软件**：直接双击脚本即可，重试机制会等代理端口起来。不用手动等。
> **如果三轮后仍报 NO-PROXY**：说明代理软件本身没正常启动，或节点是死的。先在代理软件里换节点再说。

**另一个可选入口**：`Antigravity（自动代理）.cmd` = 校准 + 启动二合一，用它开 IDE 时顺手完成校准。

**相关文件**：
| 文件 | 作用 |
|---|---|
| `E:\文档\Antigravity管理\切换代理后点我（校准Antigravity）.cmd` | 手动校准入口 v4（2026-08-26：调用的脚本已升级自愈版；纯 ASCII+CRLF，显示详细检测过程，按任意键关闭） |
| `E:\文档\Antigravity管理\Antigravity（自动代理）.cmd` | 校准+启动二合一入口（2026-08-26 更新；更新失效后双击这一个即可全自动修复+启动） |
| `E:\文档\Antigravity管理\Sync-AntigravityProxy.ps1` | 检测+改配置主脚本 **v3.0 自愈版**（2026-08-26：先检测劫持套件缺失并从 `antigravity-proxy-setup\extracted\` 自动重部署，再做端口校准；备份路径按脚本所在目录推导；纯 ASCII，无编码风险） |
| `E:\文档\Antigravity管理\sync.log` | 历次检测日志（`REDEPLOYED` = 更新清空后已自动恢复） |

---

## 三、日常验证（每天早上 / 出问题时按顺序查）

### 第 1 步：确认代理软件在运行
三个软件**只开一个**（同时开多个会抢端口或路由冲突），看右下角托盘图标在不在。

### 第 2 步：确认端口在监听（10 秒）
右键开始菜单 → 终端（或 Windows PowerShell），粘贴执行：

```powershell
Test-NetConnection 127.0.0.1 -Port 7897
```
> 端口换成你当前用的软件对应的值：Clash Verge=7897，v2rayN=10808，Mesl=7688

- 显示 `TcpTestSucceeded : True` → 正常，进入第 3 步
- 显示 `False` → 代理软件没启动或端口不对，先解决这个

### 第 3 步：确认 Antigravity 已走代理
打开目录：
```
C:\Users\Administrator\AppData\Local\Programs\antigravity\
```
- 找到当天生成的 `proxy` 开头的日志文件（如 `proxy.log` 或 `logs\proxy-20260822.log`）
- 用记事本打开，看到 **"隧道建立成功"** → 一切正常
- 日志不存在 → DLL 没加载，看「五、故障排查表」

### 一键体检命令（可选，复制即用）
```powershell
Test-NetConnection 127.0.0.1 -Port 7688 -InformationLevel Quiet; Test-Path "C:\Users\Administrator\AppData\Local\Programs\antigravity\version.dll"
```
两个都返回 `True` = 代理端口活着 + 劫持文件在位。

---

## 四、更新后怎么处理

### 4.1 Antigravity 更新后（最重要，必看）

**Antigravity 每次自动更新都会清掉安装目录里的 version.dll、dbghelp.dll 和 config.json**，表现为：突然又不能联网了。

**✅ 现在的处理方式（2026-08-26 起，脚本已升级为自愈版）：**

校准脚本 v3.0 会**自动检测文件缺失并从备份文件夹重部署**，所以更新后只需要：

1. **双击**：`E:\文档\Antigravity管理\Antigravity（自动代理）.cmd`
   - 自动恢复缺失的 version.dll / dbghelp.dll / config.json
   - 自动把 config.json 校准到当前在跑的代理软件
   - 然后自动启动 Antigravity
   - 一气呵成，什么都不用手动做
2. 或者双击 `切换代理后点我（校准Antigravity）.cmd` 只做修复校准、不启动 IDE（日志里出现 `REDEPLOYED` = 文件已自动恢复）

> 💡 也可以直接喊 WorkBuddy 里的我：「Antigravity 更新后代理失效了，重新部署一下」，我会自动完成。

**🔧 手动重部署（备用方法，脚本不可用时）：**

1. 打开备份文件夹：
   ```
   E:\文档\Antigravity管理\antigravity-proxy-setup\extracted\
   ```
2. 复制里面的 `version.dll`、`dbghelp.dll` 和 `config.json`
3. 粘贴到 Antigravity 安装目录：
   ```
   C:\Users\Administrator\AppData\Local\Programs\antigravity\
   ```
4. 重启 Antigravity，按「三、日常验证」第 3 步确认日志

> 📌 2026-08-26 实录：Antigravity 2.9.1 → 2.10.0 更新清空了上述三个文件，v2.2 劫持套件在新版上验证兼容（DLL 加载成功、全部 Hook 安装成功、无崩溃），脚本自愈逻辑实测通过。

### 4.2 代理软件更新后（v2rayN / Clash Verge / Mesl）

一般**无需任何操作**，端口号不会变。只需在更新后做一次「三、日常验证」第 2 步确认端口还在监听。

例外情况：如果更新后软件重置了设置导致端口变化 → 按「二、端口速查表」最右列找到新端口，同步改 config.json。

### 4.3 antigravity-proxy 工具本身升级

去 GitHub 看有没有新版：https://github.com/yuaotian/antigravity-proxy/releases
- 有新版本：下载 x64 的 zip，解压后用新的 `version.dll` 替换安装目录里的旧文件（`config.json` 会保留你自己的端口配置，建议也对照新版默认配置看有没有新字段）
- 没有刚需（当前能用）可以不追新

---

## 五、故障排查表

| 症状 | 原因 | 处理 |
|---|---|---|
| Antigravity 完全无网络，proxy 日志不存在 | DLL 没加载 | ① 检查 version.dll 是否还在安装目录（可能被更新清掉）② 火绒/杀毒软件拦截了注入 → 把 `C:\Users\Administrator\AppData\Local\Programs\antigravity\` 整个目录加入火绒信任区 |
| 日志里有"隧道建立成功"，但 Agent 报 `Agent execution terminated due to error` 或 `User location is not supported` | **出口节点 IP 被 Google 拒绝**（机房 IP 常见），不是 DLL 问题 | 在代理软件里换节点，优先选标注"住宅/原生/IPLC"的节点，换完直接重试 |
| 启动 Antigravity 弹 0xc0000142 错误 | 缺少运行库或 DLL 位数不对 | 安装"微软常用运行库合集"；确认用的是 x64 版 version.dll |
| 代理软件开着但端口测试 False | 软件没正常启动核心 / 端口被改 | 重启代理软件；在软件设置里核对实际端口 |
| 换了代理软件后 Antigravity 断网 | config.json 端口没跟着改，或**改的端口实际没在监听** | 按「二、切换代理软件的操作」改端口并重启 Antigravity；改之前先用 Test-NetConnection 和 curl 实测端口 |
| **运行校准脚本报 NO-PROXY（三个软件都不通）** | **最常见：刚切完代理软件，新软件端口还没起来就检测了**（启动到开端口有 3~10 秒延迟）；其次：代理软件没开、或节点死了 | v2 脚本已内置 3 轮重试（间隔 5 秒），通常等一轮就通；如果三轮后仍 NO-PROXY：① 确认代理软件确实在运行（托盘图标）② 在代理软件里测速换节点 ③ 手动验证 `curl.exe -x socks5h://127.0.0.1:10808 -s -o NUL -w "%{http_code}" http://www.gstatic.com/generate_204` 返回 204 |
| 登录报错 `dial tcp 198.18.x.x:443 ... actively refused` | DLL 正常（198.18.x.x 是 FakeIP），但 config.json 指的端口上**没有代理软件在听** | 检查代理软件是否启动、config.json 的 port/type 是否与实际监听一致（Mesl 是 7688/http，不是 7893/socks5）。**2026-08-24 实例**：从 Mesl 换成 v2rayN 后校准脚本没跑成，config.json 停在 7688 → 跑一遍校准脚本切到 socks5/10808 即恢复 |
| 双击「切换代理后点我」报 `'roxy' / 'AFTER' / 'hell.exe' 不是内部或外部命令` | .cmd 被以 **LF 换行**保存（cmd.exe 必须 CRLF），解析器按错误字节偏移执行，吃掉每行开头字符 | 2026-08-24 已重写为 v3：纯 ASCII + CRLF + `%~dp0` 自定位路径（文件内不再含中文路径，任何编码下都安全）；若再出现同类报错，用 CRLF 重写该 .cmd 即可 |
| 本地端口通、百度通，但 Google 系全 000 | 当前节点死了或被墙 | 在代理软件里测速并换节点，再验证 `curl.exe -x http://127.0.0.1:端口 ... gstatic.com/generate_204` 返回 204 |
| 时好时坏、偶发断连 | 节点质量问题 | 换节点；与本地配置无关 |

### 日志位置速查

| 日志 | 位置 | 看什么 |
|---|---|---|
| antigravity-proxy 日志 | Antigravity 安装目录下 `proxy*.log` 或 `logs\` | 注入是否成功、"隧道建立成功" |
| Antigravity 官方日志 | `%APPDATA%\Antigravity\logs\` 最新目录下 `ls-main.log` | `User location is not supported` = 换节点 |

---

## 六、关键文件位置清单（收藏这一段）

| 用途 | 路径 |
|---|---|
| Antigravity 安装目录（劫持文件在这里） | `C:\Users\Administrator\AppData\Local\Programs\antigravity\` |
| 代理配置文件（改端口就改它） | 同上目录下 `config.json` |
| 部署文件备份（重部署从这里复制） | `E:\文档\Antigravity管理\antigravity-proxy-setup\extracted\` |
| Clash Verge 端口配置 | `%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\verge.yaml` |
| v2rayN 端口配置 | `D:\Software\v2rayN-windows-64-desktop\v2rayN-windows-64\guiConfigs\guiNConfig.json` |
| Mesl 端口配置（参考，可能失真） | `%APPDATA%\cloud.mesl\mesl_lite\runtime.yaml`（⚠️ 此文件含节点明文凭据，勿外发；端口以实测监听为准） |

---

## 七、一句话口诀

> **随便开哪个代理软件（不用开 TUN）→ 换了软件就双击「切换代理后点我」→ 重启 Antigravity = 正常。
> 突然不能用了 = 八成是 Antigravity 更新清了文件，双击「Antigravity（自动代理）」即可自动恢复（v3.0 自愈版，2026-08-26 起）。**

---

## 八、维护记录

| 日期 | Antigravity 版本 | 事件 / 动作 | 结果 |
|---|---|---|---|
| 2026-08-27 | 未知（更新后） | 更新清空了 3 个劫持文件，自愈脚本 v3.0 重部署 + 校准端口 | REDEPLOYED 3 files → SWITCHED 至 v2rayN socks5://127.0.0.1:10808，Google 204 通 |
