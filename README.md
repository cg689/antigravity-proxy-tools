# Antigravity 免 TUN 代理修复工具集

一键修复 **Antigravity 自动更新导致代理失效**的问题，并自动校准本地代理端口。

## 背景

本机 Antigravity 使用 **DLL 劫持** 实现免 TUN 进程级代理：在安装目录放入 `version.dll`、`dbghelp.dll`、`config.json` 三个文件，通过劫持系统 DLL 把 Antigravity 及子进程的流量透明转发到本地代理软件（Clash / v2rayN / Mesl 等）。

**已知行为**：Antigravity 每次自动更新都会清空这 3 个文件，代理随之失效。

## 原理

本工具集围绕一个自愈脚本 `Sync-AntigravityProxy.ps1`（v3.1）运转，分两个阶段：

1. **SELF-HEAL（自愈）**：检测安装目录 3 个劫持文件是否缺失，缺失则从本地备份 `antigravity-proxy-setup/extracted/` 自动恢复。
2. **CALIBRATE（校准）**：依次探测 9 个常见 Windows 代理软件的默认端口——先看端口是否在监听，再实测能否连通 Google（`gstatic.com/generate_204` 返回 204），把 `config.json` 自动指向第一个可用的代理。

   内置候选清单（按优先级）：

   | 代理软件 | 端口 | 协议 |
   |---|---|---|
   | Clash Verge / Rev | 7897 | socks5 |
   | Clash / Clash for Windows / Mihomo / FlClash | 7890 | http |
   | v2rayN | 10808 | socks5 |
   | v2rayN | 10809 | http |
   | Shadowsocks | 1080 | socks5 |
   | NekoBox / NekoRay | 2080 | socks5 |
   | Hiddify-Next | 12334 | socks5 |
   | Qv2ray | 1089 | socks5 |
   | Mesl Lite | 7688 | http |

> 校验使用 `socks5h` 而非 `socks5`（远端 DNS 解析），避免国内 DNS 污染造成误判。

## 快速开始

### 日常使用 / Antigravity 更新后

1. 打开任意代理软件（Clash / v2rayN / Shadowsocks / NekoBox / Hiddify 等，不用开 TUN）
2. **双击 `Antigravity（自动代理）.cmd`**
3. 自动完成「恢复劫持文件 → 校准端口 → 启动 Antigravity」

### 换了代理软件后

1. 打开新代理软件
2. **双击 `切换代理后点我（校准Antigravity）.cmd`**（只校准不启动，显示详细日志）
3. 手动重启 Antigravity

### 手动验证

```bash
# 查看劫持文件是否齐全
ls "%LOCALAPPDATA%\Programs\antigravity\" | grep -E "version|dbghelp|config"
# 查看历次校准日志
Get-Content sync.log -Tail 5
```

## 目录结构

```
├── Sync-AntigravityProxy.ps1           # 自愈主脚本 v3.1（唯一需要更新的核心）
├── Antigravity（自动代理）.cmd          # 日常入口：自愈 + 校准 + 启动
├── 切换代理后点我（校准Antigravity）.cmd # 手动入口：自愈 + 校准（不启动）
├── antigravity-proxy-setup/
│   ├── antigravity-proxy-v2.2-win-x64.zip   # 上游发布包原样备份
│   └── extracted/                           # 解压后的劫持文件备份（重部署来源）
│       ├── version.dll      # 核心劫持 DLL
│       ├── dbghelp.dll      # agy.exe CLI 需要的 shim
│       ├── config.json      # 代理配置模板
│       ├── config-web.html  # 可视化配置页
│       └── 使用说明.md      # 上游使用说明（原文）
├── Antigravity免TUN代理-日常验证与更新维护手册.md  # 完整运维手册（含排障速查）
├── 提示词-Antigravity更新修复.md                 # 发给 AI 的自动修复指令
└── README.md
```

## 适配说明

- 安装目录**自动探测**：默认 `%LOCALAPPDATA%\Programs\antigravity`，不存在时自动扫描 `%LOCALAPPDATA%\Programs` 下最新的 `antigravity*` 目录，无需改代码。
- 代理端口**候选清单可扩展**：脚本顶部 `$candidates` 数组是唯一配置点，用其他代理软件只需加一行 `@{ name="..."; port=端口; type="socks5"/"http" }`。
- 备份目录与日志目录基于脚本自身位置（`$PSScriptRoot`）派生，整个文件夹拷贝到任意位置均可运行。
- `.cmd` 文件保持纯 ASCII + CRLF（cmd.exe 对 LF 换行解析会出错）；`.ps1` 保持 UTF-8 带 BOM。

## 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 双击 .cmd 后代理仍不通 | 劫持文件缺失但脚本未提权写入失败 | 以管理员运行 .cmd；或用 PowerShell 提权执行 `Sync-AntigravityProxy.ps1` |
| DLL 正常但对话报网络错误 | 节点出口 IP 被 Google 判定不可用 | 在代理软件里换「非机房/住宅」节点，与本地配置无关 |
| 输出 `NO-PROXY` | 所有候选端口都连不通 Google | 检查代理软件是否启动、节点是否存活 |

## 上游项目与版权

- 劫持方案及 DLL 来自开源项目 **[yuaotian/antigravity-proxy](https://github.com/yuaotian/antigravity-proxy)**（v2.2，win-x64），`extracted/` 下的 `version.dll`、`dbghelp.dll`、`config.json`、`config-web.html`、`使用说明.md` 均属该项目产物，版权归原作者。
- 本仓库自研部分（`Sync-AntigravityProxy.ps1`、两个 `.cmd`、手册、提示词、`README.md`）供个人学习与运维使用，可自由复制修改。

> 免责声明：DLL 劫持属于系统级注入技术，仅建议用于自己机器上的官方应用流量代理；请遵守当地法律与目标软件服务条款。
