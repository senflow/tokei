# Tokei 多设备数据同步 — 配置指南

交互式引导用户完成 Tokei 多设备同步的全部配置。

## 触发

用户说 "setup tokei"、"配置 tokei 同步"、"tokei sync setup"、"设置用量同步" 时触发。

## 架构说明

- 每台设备独立运行 `usage.30s.py` 采集本机 AI 用量，生成 `<device_id>.json`
- 所有设备通过一个 **私有 Git 仓库** (`~/.tokei/sync/`) 同步数据
- Mac 端 Tokei.app 聚合所有设备数据展示；Linux 端通过 crontab 自动采集+推送
- 采集脚本从 `https://raw.githubusercontent.com/senflow/tokei/main/usage.30s.py` 下载

## 执行流程

按以下步骤逐一检查和执行，已完成的步骤跳过：

### 步骤 1: 检查环境

```bash
which git >/dev/null 2>&1 && echo "✅ git" || echo "❌ git"
which python3 >/dev/null 2>&1 && echo "✅ python3" || echo "❌ python3"
which gh >/dev/null 2>&1 && echo "✅ gh CLI" || echo "⚠️ gh CLI 未安装(可选，手动配置也行)"
[ -d ~/.tokei/sync/.git ] && echo "✅ 同步仓库已存在" || echo "⏳ 同步仓库未配置"
[ -f ~/.tokei/config.json ] && echo "✅ 本机配置存在" || echo "⏳ 本机未配置"
crontab -l 2>/dev/null | grep -q tokei && echo "✅ crontab 已配置" || echo "⏳ crontab 未配置"
```

如果缺少 git 或 python3，提示安装后继续。

### 步骤 2: 安装采集脚本

```bash
mkdir -p ~/.tokei
curl -fsSL https://raw.githubusercontent.com/senflow/tokei/main/usage.30s.py -o ~/.tokei/usage.30s.py
chmod +x ~/.tokei/usage.30s.py
echo "✅ 采集脚本已安装"
```

### 步骤 3: 配置同步仓库

判断当前场景：

**场景 A — 首台设备（需要创建仓库）：**

```bash
# 有 gh CLI
gh repo create tokei-sync --private
git clone $(gh repo view tokei-sync --json sshUrl -q .sshUrl) ~/.tokei/sync

# 没有 gh CLI — 提示用户手动在 GitHub 创建私有仓库 tokei-sync，然后：
git clone git@github.com:<用户名>/tokei-sync.git ~/.tokei/sync
```

初始化并推送：

```bash
cd ~/.tokei/sync
git add -A && git commit -m "init" && git push -u origin main
```

**场景 B — 加入已有仓库（其他设备已配好）：**

询问用户仓库地址，然后：

```bash
git clone <仓库地址> ~/.tokei/sync
```

### 步骤 4: 写入本机配置

```bash
DEVICE_NAME=$(hostname -s)
cat > ~/.tokei/config.json <<EOF
{
  "device_id": "$DEVICE_NAME",
  "sync_dir": "~/.tokei/sync",
  "auto_sync": false,
  "sync_interval": 5
}
EOF
echo "✅ 本机配置完成: $DEVICE_NAME"
```

### 步骤 5: 配置定时采集（Linux/远程服务器）

Mac 端由 Tokei.app 负责采集，跳过此步。仅 Linux/远程服务器需要：

```bash
cat > ~/.tokei/tokei-sync.sh <<'SH'
#!/bin/sh
set -e
cd "$HOME/.tokei/sync"
python3 "$HOME/.tokei/usage.30s.py" --json >/dev/null
git fetch -q origin main
device_file=$(find . -maxdepth 1 -type f -iname "$(hostname -s).json" -print -quit)
[ -n "$device_file" ] || device_file="./$(hostname -s).json"
git add -- "$device_file"
git diff --cached --quiet || git commit -qm "sync $(hostname -s)"
git rebase -q origin/main
git push -q origin HEAD:main
SH
chmod +x ~/.tokei/tokei-sync.sh
(crontab -l 2>/dev/null | grep -v 'tokei-sync.sh'; echo '*/5 * * * * ~/.tokei/tokei-sync.sh') | crontab -
echo "✅ crontab 已配置，每 5 分钟自动采集并同步"
```

同步脚本只 add 自己的设备文件、fetch+rebase+push，避免多设备并发同步时互相提交/覆盖对方文件。

### 步骤 6: 验证

```bash
# 立即采集一次
cd ~/.tokei/sync && python3 ~/.tokei/usage.30s.py --json >/dev/null 2>&1

# 检查生成的数据文件
DEVICE_NAME=$(cat ~/.tokei/config.json | python3 -c 'import sys,json;print(json.load(sys.stdin)["device_id"])')
[ -f ~/.tokei/sync/${DEVICE_NAME}.json ] && echo "✅ 数据文件已生成" || echo "❌ 数据文件未找到"

# 推送(只 add 自己的设备文件)
cd ~/.tokei/sync && git add -- "${DEVICE_NAME}.json" && git diff --cached --quiet || git commit -m "sync $DEVICE_NAME" && git push
echo ""
echo "═══ 完成 ═══"
echo "  本机: $DEVICE_NAME"
ls ~/.tokei/sync/*.json 2>/dev/null | while read f; do
    name=$(basename "$f" .json)
    echo "  📱 $name"
done
```

### 步骤 7: 提示后续

- **Mac 用户**：Tokei 菜单栏 → 设置 → 多设备同步 → 开启即可
- **其他设备**：在新设备上重复步骤 1-6，clone 同一个仓库即可加入

## 交互策略

- 每一步执行前先告诉用户要做什么，得到确认后再执行
- 已完成的步骤直接跳过并显示 ✅
- 首先判断场景：首台设备 vs 加入已有仓库
- 判断平台：Mac(跳过 crontab) vs Linux(需要 crontab)
- 出错时给出具体的修复建议

## 回答风格

简洁直接，每步一行结果。不要长段解释。像 CLI 安装向导一样。
