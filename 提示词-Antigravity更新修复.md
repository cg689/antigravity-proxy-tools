# 提示词：Antigravity 更新后修复代理（发给 AI 直接执行）

> **用法**：Antigravity 更新后代理失效时，对 AI 说一句——  
> **「antigravity更新了，请按 E:\文档\Antigravity管理\提示词-Antigravity更新修复.md 执行」**  
> （或直接把本文件全文粘贴给 AI）
>
> 校订：2026-08-27 · 适配 Antigravity 2.10.0 / antigravity-proxy v2.2 / 自愈脚本 v3.2



---

## 给 AI 的执行指令（从这里开始照做）

**背景**：本机 Antigravity 用 DLL 劫持实现免 TUN 进程级代理，靠安装目录里 3 个文件工作：`version.dll`、`dbghelp.dll`、`config.json`。Antigravity **每次自动更新都会删掉这 3 个文件**（已知行为），代理因此失效。

**核心认知（先读，避免绕弯路）**：已有自愈脚本 `E:\文档\Antigravity管理\Sync-AntigravityProxy.ps1`（v3.0），能自动重部署文件 + 校准代理端口。**99% 的情况不需要写新代码，跑一次自愈脚本就修完了**。只有 Step 3 的异常分支才需要动脚本。

### Step 0 · 环境诊断（Bash 工具）

```bash
# ① 劫持文件是否缺失（更新后的典型状态：3 个文件全没了）
ls "/c/Users/Administrator/AppData/Local/Programs/antigravity/" | grep -E "version|dbghelp|config"

# ② Antigravity 是否在运行（运行中文件被占用，需先请用户关闭）
tasklist | grep -i antigravity

# ③ 当前哪个代理端口在监听（Clash=7897/7890、v2rayN=10808/10809、SS=1080、NekoBox=2080、Hiddify=12334、Qv2ray=1089、Mesl=7688）
netstat -ano | grep LISTENING | grep -E ":(7897|7890|10808|10809|1080|2080|12334|1089|7688)\s"
```

- ① 输出为空或缺文件 → 正常，正是更新导致的，继续 Step 1
- ① 报目录不存在 → 走 Step 3-A
- ② 有进程 → 先请用户关闭 Antigravity 再继续

### Step 1 · 提权运行自愈脚本（PowerShell 工具 + dangerouslyDisableSandbox=true）

不提权的话，对 C 盘 Program 目录的写入会被沙箱**静默拦截**（显示成功、实际没落盘）：

```powershell
& 'E:\文档\Antigravity管理\Sync-AntigravityProxy.ps1' *>&1 | Out-String | Out-File -FilePath 'E:\文档\Antigravity管理\last-run-output.txt' -Encoding UTF8
```

然后用 Read 工具读 `E:\文档\Antigravity管理\last-run-output.txt`（PowerShell 工具偶尔不回显，落盘再读最稳）。

**预期输出**：`REDEPLOYED ... files`（或 `OK ... present`）+ `SWITCHED to <端口>`（或 `OK proxy unchanged`）。

### Step 2 · 验证落盘（Bash 工具）

```bash
# ① 三个文件都在了
ls "/c/Users/Administrator/AppData/Local/Programs/antigravity/" | grep -E "version|dbghelp|config"
# ② config 指向当前监听的端口（Step 0-③ 查到的那个）
head -8 "/c/Users/Administrator/AppData/Local/Programs/antigravity/config.json"
# ③ 日志记录了本次操作
tail -3 "/e/文档/Antigravity管理/sync.log"
```

三项全过 → 跳 Step 4。

### Step 3 · 异常分支（仅 Step 1/2 失败时才进来）

**3-A 安装路径变了**：搜 `C:\Users\Administrator\AppData\Local\Programs\` 下新的 antigravity 目录，找到后改自愈脚本顶部的路径配置，重跑 Step 1。

**3-B 代理端口不在候选清单**（用户用了清单外的代理软件或自定义端口）：脚本 v3.2 起已内置 9 个常见软件默认端口（Clash Verge 7897 / Clash·Mihomo 7890 / v2rayN 10808·10809 / Shadowsocks 1080 / NekoBox 2080 / Hiddify 12334 / Qv2ray 1089 / Mesl 7688），且清单全失败时会**自动扫描本机所有监听端口**逐个测 http/socks5，自定义端口也能自动识别。仅当动态扫描也找不到（代理没开或节点死了）时才需排查代理软件本身，一般无需改脚本。

**3-C 疑似 DLL 与新版不兼容**（文件都在但代理不通）：

1. 查 <https://github.com/yuaotian/antigravity-proxy/releases> 有无 v2.2 之后的新版；有则下载解压，更新备份目录 `E:\文档\Antigravity管理\antigravity-proxy-setup\extracted\`，重跑 Step 1
2. 无新版则查该仓库 issues
3. 先看 `C:\Users\Administrator\AppData\Local\Programs\antigravity\logs\proxy-当天日期.log`：有「加载成功 / Hook 安装成功」→ DLL 正常，问题在代理节点，不是本方案

**改文件时的硬性要求（历史踩坑，必须遵守）**：

- `.cmd` 文件：内容必须**纯 ASCII + CRLF**，写完执行 `unix2dos <文件>` 并用 `file <文件>` 确认（含中文或 LF 会执行异常）
- `.ps1` 文件：UTF-8 **带 BOM**

### Step 4 · 收尾与汇报

1. 请用户**双击 `E:\文档\Antigravity管理\Antigravity（自动代理）.cmd`** 启动验证（AI 工具会话里启动 GUI 无法驻留，属环境限制，不要反复尝试、不要误判为故障）
2. 用户启动后可查 `C:\Users\Administrator\AppData\Local\Programs\antigravity\logs\proxy-YYYYMMDD.log`，出现「加载成功 / Hook 安装成功」即彻底修复
3. 在 `E:\文档\Antigravity管理\Antigravity免TUN代理-日常验证与更新维护手册.md` 追加一行维护记录（日期 + Antigravity 版本 + 本次动作；无记录表则加在文末）
4. 删除临时文件 `last-run-output.txt`
5. 向用户汇报：做了什么、验证结果；若代理仍不通，提示「大概率是节点 IP 被 Google 拒，换个节点即可」

## 已知坑速查（执行中随时对照）

| 坑              | 现象                            | 解法                                        |
| -------------- | ----------------------------- | ----------------------------------------- |
| 沙箱静默拦截         | 写 C 盘 Program 目录"成功"但文件没落盘    | PowerShell 工具 + dangerouslyDisableSandbox |
| PowerShell 不回显 | 工具返回空输出                       | 输出重定向到文件，再用 Read 读                        |
| GUI 无法驻留       | 各种方式启动 Antigravity 进程秒退、无崩溃转储 | 环境限制，请用户双击验证，别误判为 DLL 不兼容                 |
| cmd 乱码         | .cmd 含中文或 LF 换行               | 重写为纯 ASCII + unix2dos                     |
| "假死"误判         | DLL 加载成功但 Agent 报网络错误         | 是节点 IP 被 Google 拒，换节点，别动配置                |

## 文件地图

| 路径                                                                | 说明                     |
| ----------------------------------------------------------------- | ---------------------- |
| `E:\文档\Antigravity管理\Sync-AntigravityProxy.ps1`                   | 自愈主脚本 v3.0（每次要跑的就是它）   |
| `E:\文档\Antigravity管理\antigravity-proxy-setup\extracted\`          | 3 个劫持文件的永久备份（重部署来源）    |
| `E:\文档\Antigravity管理\切换代理后点我（校准Antigravity）.cmd`                  | 手动校准入口                 |
| `E:\文档\Antigravity管理\Antigravity（自动代理）.cmd`                       | 校准+启动二合一入口（用户日常用这个）    |
| `E:\文档\Antigravity管理\sync.log`                                    | 历次校准日志                 |
| `E:\文档\Antigravity管理\Antigravity免TUN代理-日常验证与更新维护手册.md`            | 完整维护手册（人类视角，含原理）       |
| `C:\Users\Administrator\AppData\Local\Programs\antigravity\`      | Antigravity 安装目录（部署目标） |
| `C:\Users\Administrator\AppData\Local\Programs\antigravity\logs\` | DLL 代理日志（验证加载用）        |
