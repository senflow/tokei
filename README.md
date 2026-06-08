<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_13+-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/python-3.8+-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python 3.8+">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
  <a href="https://github.com/cclank/tokei/stargazers"><img src="https://img.shields.io/github/stars/cclank/tokei?style=flat-square&color=yellow" alt="Stars"></a>
  <a href="https://github.com/cclank/tokei/releases"><img src="https://img.shields.io/github/v/release/cclank/tokei?style=flat-square&color=blue" alt="Release"></a>
</p>

<h1 align="center">⏱ Tokei 時計</h1>

<p align="center">
  <strong>AI Coding Usage Monitor for macOS</strong><br>
  <sub>了然于心，掌控全局。</sub><br><br>
  <a href="https://tokei.lanshuagent.com">🌐 Homepage</a> · <a href="https://dl.lanshuagent.com/tokei/Tokei.dmg">⬇️ Download</a>
</p>

---

## What is Tokei?

Tokei is a **macOS menu bar app** that tracks usage, cost, and performance across **8 AI coding tools** in real-time — all from local log files, with zero network traffic.

| Tool | Metrics |
|------|---------|
| **Claude Code** | Tokens (in/out/cache), cost, quota, models |
| **Codex CLI** | Tokens, cost, quota, sessions |
| **Gemini CLI** | Tokens, thoughts, cost, models |
| **Grok CLI** | Tokens, sessions, context |
| **Aider (Hermes)** | Tokens, cost, cache hit, models |
| **OpenClaw** | Tokens, cost, tasks, models |
| **OpenCode** | Tokens, cost, cache hit, models |
| **Qoder** | Tokens, calls, quota |

## Features

- **Real-time monitoring** — 30s auto-refresh, menu bar quota display
- **Cost estimation** — Per-model pricing via external `pricing.json`, auto-updatable
- **Multi-device sync** — Git-based sync across Mac + Linux servers
- **Time ranges** — Today / Yesterday / Week / Last Week / Month / Year
- **Dashboard** — Daily cost chart, weekly heatmap, tool breakdown
- **Privacy-first** — Reads local logs only, never phones home
- **Wrapped** — Annual review of your AI coding journey
- **Sit reminder** — Idle-aware break notifications

## Quick Start

```bash
# Download and install
curl -LO https://dl.lanshuagent.com/tokei/Tokei.dmg
open Tokei.dmg
# Drag Tokei.app to Applications
```

Or build from source:

```bash
git clone https://github.com/cclank/tokei.git
cd tokei/Tokei
bash package.sh
open Tokei.app
```

## Architecture

```
usage.30s.py              # Python collector — scans local logs, outputs JSON
pricing.json              # Model pricing table (--update-prices to refresh)
pricing_overrides.json    # Local price overrides (not overwritten on refresh)
Tokei/
├── Sources/Tokei/
│   ├── Model.swift       # Data models (Usage, *Range, *Stat)
│   ├── PanelView.swift   # Main UI — cards, settings, footer
│   ├── DataLoader.swift  # Runs Python script, decodes JSON
│   ├── SyncManager.swift # Multi-device merge via Git
│   ├── DashboardView.swift
│   ├── Design.swift      # Theme, colors, shared components
│   └── main.swift        # App entry, menu bar, status item
└── package.sh            # Build + package into .app/.dmg
```

## Data Sources

All data is read from **local log files only**. No network, no API calls (except the explicit `--update-prices` command).

| Tool | Log Path |
|------|----------|
| Claude Code | `~/.claude/projects/<proj>/<session>.jsonl` |
| Codex CLI | `~/.codex/sessions/YYYY/MM/DD/*.jsonl` |
| Gemini CLI | `~/.gemini/gemini-cli/conversations/*.json` |
| Grok CLI | `~/.grok/sessions/YYYY/MM/DD/*.jsonl` |
| Aider | `~/.aider/analytics/analytics.jsonl` |
| OpenClaw | `~/.openclaw/agents/*/sessions/*.jsonl` + SQLite |
| OpenCode | `~/.opencode/sessions/*.json` |
| Qoder | `~/.qodo-ai/sessions/*.jsonl` |

## Cost Estimation

Costs are **estimated at API prices**, not subscription fees. The pricing table is external (`pricing.json`, sourced from OpenRouter) and can be refreshed:

```bash
python3 usage.30s.py --update-prices   # Only networked action in the entire tool
```

Local overrides go in `pricing_overrides.json` (preserved across updates). Unknown models fall back by family keyword, then to Opus pricing (conservative upper bound).

## Multi-Device Sync

Tokei supports syncing usage data from multiple machines via a private Git repo.

**On your Mac:** Open Settings → Multi-device Sync → Enable, then select a sync directory (a Git repo).

**On a remote Linux server:**

```bash
git clone <your-private-repo> ~/.tokei/sync
cp ~/.tokei/sync/usage.30s.py ~/.tokei/
echo '{"sync_dir":"~/.tokei/sync","device_id":"'$(hostname -s)'"}' > ~/.tokei/config.json
# Auto-sync every 5 minutes
(crontab -l 2>/dev/null; echo '*/5 * * * * cd ~/.tokei/sync && python3 ~/.tokei/usage.30s.py --json >/dev/null && git pull -q && git add -A && git diff --cached --quiet || git commit -qm sync && git push -q') | crontab -
```

## Star History

<p align="center">
  <a href="https://star-history.com/#cclank/tokei&Date">
    <img src="https://api.star-history.com/svg?repos=cclank/tokei&type=Date" width="600" alt="Star History Chart">
  </a>
</p>

## License

MIT
