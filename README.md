<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_13+-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/python-3.8+-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python 3.8+">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
  <a href="https://github.com/senflow/tokei/stargazers"><img src="https://img.shields.io/github/stars/senflow/tokei?style=flat-square&color=yellow" alt="Stars"></a>
  <a href="https://github.com/senflow/tokei/releases"><img src="https://img.shields.io/github/v/release/senflow/tokei?style=flat-square&color=blue" alt="Release"></a>
</p>

<h1 align="center">⏱ Tokei 知度</h1>

<p align="center">
  <strong>macOS 菜单栏 AI 编程用量监控</strong><br>
  <sub>了然于心，掌控全局。</sub><br><br>
  <a href="https://github.com/senflow/tokei/releases/latest">⬇️ 下载</a> · <a href="#english">English</a>
</p>

---

> 本仓库 fork 自 [cclank/tokei](https://github.com/cclank/tokei)，在其 MIT 协议基础上继续开发。想了解具体改了什么，看下面的「本 Fork 相对上游的修改」。

## 什么是 Tokei？

Tokei 是一款 **macOS 菜单栏应用**，实时追踪你在 **9 款 AI 编程工具** 上的用量、成本和性能——默认全部基于本地日志，零网络流量。

## 本 Fork 相对上游的修改

本仓库基于上游 [cclank/tokei](https://github.com/cclank/tokei) v1.0.9 分叉，之后**有选择地**移植了上游 v1.0.10 ~ v1.0.12 的部分修复，并加了几个自己的功能。不是照单全收上游的每个改动,下面是完整清单:

**从上游选择性合并的修复：**
- Codex 跨 rollout（子代理 / 分叉任务）去重：修复子代理重放父任务历史导致 token / 成本被重复计入的问题
- Codex 配额窗口按时长（`window_minutes`）识别，不再假设 primary=5h / secondary=周，兼容新版 Codex 返回结构
- 多设备同步稳定性：同步脚本只 `add` 自己的设备文件、`fetch`+`rebase`+`push`，避免多设备并发推送互相冲突；`config.json` 改成合并写入，不再整体覆盖丢失其他字段
- Qoder IDE 开关状态启动时主动落盘，修复首次启动不采集数据的问题
- Gemini CLI 扫描器支持新版增量 `.jsonl` 会话日志（旧版整份快照 `.json` 仍兼容）
- OpenCode 扫描器支持新版 SQLite 用量采集（`opencode.db`），旧版逐消息 JSON 作为补充来源
- Pi Coding Agent 扫描器支持 Oh My Pi(OMP)fork 的会话目录
- Claude/Gemini/Pi/新工具的每日统计补充 `hours[24]` 逐小时字段,回顾页作息分析覆盖面更广
- 新增 Qwen Code CLI、ZCode、MiMoCode、WorkBuddy 四款工具的本地用量采集
- 开机自启动加 LaunchAgent 兜底：ad-hoc 签名的 app 重新签名后 `SMAppService` 注册容易失效，现在会自动用 LaunchAgent 兜底并在每次启动时自愈
- 自动更新加固：SHA256 校验下载包、仅信任 GitHub 域名、原子安装+签名校验失败自动回滚

**没有跟的：**
- Codex 实时配额联网拉取——上游默认**开启**（用 Codex 登录态请求官方接口）。本 fork **合并了这个能力但默认关闭**，需要显式设置环境变量 `TOKEI_CODEX_LIVE_QUOTA=1` 才会联网，维持"默认零网络、不需要登录"的定位
- 自动更新检查、GitHub 链接等均已指向本仓库，不会拉取上游发布版本或覆盖本地改动
- 上游自建 CDN(`dl.lanshuagent.com`)相关的更新元数据生成脚本——本 fork 只走 GitHub Releases,复用 GitHub API 原生的 asset digest,不需要额外脚本

**本 fork 新增的功能：**
- 多设备用量选择器：不再只是"本机 / 全部"二选一，可以从多设备列表里选中**任意一台具体设备**单独查看用量（设备名取自设置里的设备名 / deviceId）。设备数 ≤5 台时用分段控件快速切换，>5 台自动改为下拉列表，默认展示仍是"全部"
- 开机自启动开关（基于 `ServiceManagement.SMAppService`，见上方 LaunchAgent 兜底）

**移除的功能：**
- 回顾页底部"这些花费 ≈ N 杯咖啡 / N 顿火锅 / 码了 N 字"的随机彩蛋提示
- 防休眠、久坐提醒（连同对应的语音提示文件）

### 支持的工具

| 工具 | 追踪指标 |
|------|----------|
| **Claude Code** | Token（输入/输出/缓存）、成本、配额、模型 |
| **Codex CLI** | Token、成本、配额、会话 |
| **Gemini CLI** | Token、思考量、成本、模型 |
| **Grok CLI** | Token、会话、上下文 |
| **Hermes** | Token、成本、缓存命中率、模型 |
| **OpenClaw** | Token、成本、任务、模型 |
| **Pi Coding Agent CLI**（含 Oh My Pi fork） | Token、成本、缓存命中率、模型、项目 |
| **OpenCode**（SQLite + 旧版 JSON） | Token、成本、缓存命中率、模型 |
| **Qoder** | Token、调用次数、配额 |
| **Qoder CLI** | 调用次数、会话、耗时、子 agent |
| **Qwen Code CLI** | Token、成本、缓存命中率、模型 |
| **ZCode** | Token、成本、缓存命中率、模型 |
| **MiMoCode** | Token、成本、缓存命中率、模型 |
| **WorkBuddy** | Token、成本、缓存命中率、模型 |

## 功能一览

### 实时监控
- 30 秒自动刷新，菜单栏直接显示配额/用量
- 按工具展示卡片，一眼掌握所有 AI 工具状态

### 成本估算
- 基于 API 实际定价估算成本（非订阅费用）
- 317 个模型价格表（来源 OpenRouter），支持一键更新
- 本地价格覆盖（`pricing_overrides.json`），更新不丢失
- 未知模型按家族关键词回退，兜底用 Opus 价格（保守上限）

### 数据面板
- 每日成本折线图
- 每周热力图
- 工具用量占比分析

### 时间维度
- 今天 / 昨天 / 本周 / 上周 / 本月 / 今年
- 随时切换，对比不同时段用量趋势

### 项目追踪
- 按项目维度查看 Claude Code / Pi / Grok 用量
- 了解每个项目消耗了多少 Token 和成本

### 多设备同步
- 基于 Git 的跨设备同步（Mac + Linux 服务器）
- Mac 端设置里一键开启
- 远程 Linux 服务器支持 crontab 自动采集和同步
- 也可以让 Claude Code 帮你自动完成全部配置

### 年度回顾（Wrapped）
- 回顾你一整年的 AI 编程旅程
- 总用量、总成本、高峰日、工具偏好等统计

### 隐私优先
- 默认仅读取本地日志文件，从不联网上报
- 默认的网络操作只有：手动执行 `--update-prices` 更新价格表、检查应用更新
- Codex 实时配额是可选功能，默认关闭，需要显式设置环境变量 `TOKEI_CODEX_LIVE_QUOTA=1` 才会用 Codex 登录态联网请求

## 快速开始

1. 从 [GitHub Releases](https://github.com/senflow/tokei/releases/latest) 下载最新 DMG
2. 打开 DMG，将 Tokei.app 拖入 Applications 文件夹
3. 首次打开如被 macOS 拦截，在终端运行：`sudo xattr -rd com.apple.quarantine /Applications/Tokei.app`
4. 打开 Tokei 即可

<details>
<summary>从源码构建</summary>

```bash
git clone https://github.com/senflow/tokei.git
cd tokei/Tokei
bash package.sh
open Tokei.app
```
</details>

## 多设备同步配置

Tokei 支持通过私有 Git 仓库在多台机器间同步用量数据。

**Mac 端：** 打开设置 → 多设备同步 → 开启，选择一个 Git 仓库目录。

**远程 Linux 服务器：**

```bash
mkdir -p ~/.tokei
git clone <你的私有仓库> ~/.tokei/sync
curl -fsSL https://raw.githubusercontent.com/senflow/tokei/main/usage.30s.py -o ~/.tokei/usage.30s.py
cat > ~/.tokei/config.json <<JSON
{"sync_dir":"~/.tokei/sync","device_id":"$(hostname -s)","auto_sync":true,"sync_interval":5}
JSON
cat > ~/.tokei/tokei-sync.sh <<'SH'
#!/bin/sh
set -e
cd "$HOME/.tokei/sync"
git rebase --abort >/dev/null 2>&1 || true
git merge --abort >/dev/null 2>&1 || true
python3 "$HOME/.tokei/usage.30s.py" --json >/dev/null
git fetch -q origin main
device_file=$(find . -maxdepth 1 -type f -iname "$(hostname -s).json" -print -quit)
[ -n "$device_file" ] || device_file="./$(hostname -s).json"
git add -- "$device_file"
git diff --cached --quiet || git commit -qm "sync $(hostname -s)"
if ! git rebase -q origin/main >/dev/null 2>&1; then
  git rebase --abort >/dev/null 2>&1 || true
  exit 1
fi
git push -q origin HEAD:main
SH
chmod +x ~/.tokei/tokei-sync.sh
# 每 5 分钟自动采集并同步
(crontab -l 2>/dev/null | grep -v 'tokei-sync.sh'; echo '*/5 * * * * ~/.tokei/tokei-sync.sh') | crontab -
```

面板设置里的"远程采集"引导会自动生成同样的脚本（点击复制即可），跟应用内部逻辑保持一致。

## 数据来源

所有数据均来自 **本地日志文件**，无网络请求。

| 工具 | 日志路径 |
|------|----------|
| Claude Code | `~/.claude/projects/<proj>/<session>.jsonl` |
| Codex CLI | `~/.codex/sessions/YYYY/MM/DD/*.jsonl` |
| Gemini CLI | `~/.gemini/gemini-cli/conversations/*.json` |
| Grok CLI | `~/.grok/sessions/YYYY/MM/DD/*.jsonl` |
| Hermes | `~/.hermes/state.db` + `~/.hermes/profiles/*/state.db` |
| OpenClaw | `~/.openclaw/agents/*/sessions/*.jsonl` + SQLite |
| Pi Coding Agent CLI | `~/.pi/agent/sessions/<project>/*.jsonl` |
| OpenCode | `~/.opencode/sessions/*.json` |
| Qoder | `~/.qodo-ai/sessions/*.jsonl` |

## 对比 CodexBar

| 功能 | Tokei | [CodexBar](https://github.com/steipete/CodexBar) |
|------|:-----:|:---------:|
| 支持工具 | 9（专注 AI 编程 CLI） | 59+（覆盖更广，含订阅/API 类服务） |
| Token 级用量分析 | ✅ | — |
| 成本估算（317 模型） | ✅ | 部分供应商有内嵌图表 |
| 数据面板（图表 + 热力图） | ✅ | 部分供应商有 |
| 多时间维度 | 6 个 | — |
| 项目级追踪 | ✅ | — |
| 多设备同步 | ✅ | — |
| 年度回顾 | ✅ | — |
| 需要联网 | 默认否（Codex 实时配额可选开启） | 是 |
| 需要登录 | 默认否 | 是（多数供应商） |
| 数据来源 | 本地日志 | 远程 API / 浏览器 Cookie |

> CodexBar 在提供商覆盖和配额可见性上表现出色。Tokei 更深入——Token 级分析、成本趋势、项目维度拆分、跨设备同步——全部无需登录。

## 更新日志

### v1.0.10
- fix: 模型成本重算改按原始 model id 查价，不再按显示名兜底（曾导致 Fable 5 / Sonnet 5 按 Opus/Sonnet 4.6 价格计费）
- fix: 价格编辑器改用独立窗口，修复挂在菜单栏 popover 上的 `.sheet` 被外部点击关闭时卡死整个 app 的问题
- fix: 多设备同步的 commit+rebase 现在会重试，修复后台 30 秒刷新和同步竞态导致本机提交推不上去的问题
- fix: Gemini CLI 扫描器支持新版增量 `.jsonl` 会话日志
- fix: OpenCode 扫描器支持新版 SQLite 用量采集，旧版 JSON 仍作为补充来源
- fix: Pi Coding Agent 扫描器支持 Oh My Pi(OMP)fork
- feat: 新增 Qoder CLI 用量追踪
- feat: 新增 Qwen Code CLI、ZCode、MiMoCode、WorkBuddy 四款工具
- feat: Claude/Gemini/Pi/新工具补充逐小时(`hours[24]`)统计
- feat: 开机自启动加 LaunchAgent 兜底 + 自愈,不再因重新签名悄悄失效
- feat: 自动更新加固——SHA256 校验、域名白名单、原子安装失败自动回滚

### Fork 修改（基于上游 v1.0.9）
详见上面「本 Fork 相对上游的修改」。

### v1.0.9
- fix: 多设备同步按日期边界对齐，修正跨设备采集时差导致的 range 串台

### v1.0.8
- feat: 点击模型行展开详情（输入/输出/缓存读写/命中率/单价）
- feat: 回顾新增「Loop Engineering !!」「Loop滴神」成就（连续 24/7 活跃）
- fix: GLM 5.2 价格映射修复（不再按 Opus 价计算）
- fix: 同步数据成本自动修正（本地价格表重算对端模型成本）

### v1.0.7
- feat: Qoder 拆分为 CLI 和 IDE 两张独立卡片
- feat: Qoder IDE 数据采集（支持 VS Code / JetBrains 插件用量）
- fix: Qoder 分拆后数据模型和同步适配

### v1.0.6
- perf: 脚本性能优化 10 倍（6.5s→0.6s），CPU 占用从 ~22% 降至 ~1%
- fix: 首次加载失败自动重试 3 次，不再直接显示错误
- fix: Python 路径探测，解决 GUI 应用 PATH 缺失问题

### v1.0.5
- fix: 彻底消除外部 zstd 二进制依赖，根治 Gatekeeper 拦截问题
- fix: Swift 内置 CZstd 解压修复（帧边界精确定位）
- feat: 设置关闭工具卡片后菜单栏同步隐藏对应额度
- feat: 设置页手动检查更新按钮
- fix: 移除过时的 zstd 安装提示

### v1.0.4
- feat: 回顾支持时间周期筛选（今日/本周/本月/今年/全部），模型用量联动
- feat: 新增「永动机」成就（24h 全时段活跃）
- fix: 成就命名优化（俱乐部→先生）
- fix: Claude 额度条缺失时显示 zstd 安装提示

### v1.0.3
- feat: 主页顶部动态升级按钮，有新版本自动显示，一键升级
- feat: 24 小时自动检查更新
- feat: 品牌升级「時計」→「知度」(Token + Insight = Tokei)
- fix: Claude Desktop 配额条不显示（zstd 路径发现 + 二进制打包）
- fix: 下载超时保护（5 分钟）+ 失败自动恢复

### v1.0.2
- feat: 久坐提醒语音播报
- feat: 按模型显示 token 总量 + 缓存命中率
- feat: Hermes 多 profile 支持（`~/.hermes/profiles/*/state.db`）
- feat: 设置页 GitHub 链接按钮
- fix: 菜单栏无配额时兜底显示今日总 token 或品牌图标
- fix: 3 处文件句柄泄漏（Claude/Gemini/Pi 扫描）
- fix: Hermes「上周」数据缺失
- fix: OpenCode 成本纳入每日汇总

### v1.0.1
- fix: Claude Code 按 message ID 去重，修复重复计数问题
- fix: Claude Code 扫描 subagent/workflow 日志（之前遗漏）
- fix: Codex 额度过期后自动归零，解决刷新不及时问题
- feat: 设置页增加「检查更新」按钮 + "已是最新"反馈
- fix: 应用内自动更新支持

## Star History

<p align="center">
  <a href="https://star-history.com/#senflow/tokei&Date">
    <img src="https://api.star-history.com/svg?repos=senflow/tokei&type=Date" width="600" alt="Star History Chart">
  </a>
</p>

---

<a id="english"></a>

## English

Tokei is a **macOS menu bar app** that tracks usage, cost, and performance across **9 AI coding tools** in real-time — by default entirely from local log files, with zero network traffic.

This repository is a **fork of [cclank/tokei](https://github.com/cclank/tokei)**. See "本 Fork 相对上游的修改" above (in Chinese) for the full list of what was selectively merged from upstream v1.0.10–v1.0.12, what was intentionally skipped (Codex live-quota fetch defaults to **off** here, opt-in via `TOKEI_CODEX_LIVE_QUOTA=1`), and what's new in this fork (per-device usage picker for multi-device sync, launch-at-login toggle) or removed (the random cost-comparison easter egg).

**Features:** Real-time monitoring (30s refresh) · Cost estimation (317 models, OpenRouter pricing) · Dashboard (daily chart, weekly heatmap) · Time ranges (today/week/month/year) · Project-level tracking · Multi-device sync (Git-based, Mac + Linux, with a per-device usage picker) · Annual Wrapped · Privacy-first by default (local logs only; Codex live-quota network fetch is opt-in) · Launch at login

**Supported tools:** Claude Code, Codex CLI, Gemini CLI, Grok CLI, Hermes, OpenClaw, Pi Coding Agent CLI, OpenCode, Qoder

## License

MIT — see [LICENSE](LICENSE). This fork continues to be distributed under the original project's MIT license.
