#!/usr/bin/env python3
# <bitbar.title>AI Usage Bar</bitbar.title>
# <bitbar.version>v0.1</bitbar.version>
# <bitbar.author>local</bitbar.author>
# <bitbar.desc>Claude Code + Codex 本地 token / 缓存命中 / 花费 / 额度</bitbar.desc>
# <swiftbar.runInBash>false</swiftbar.runInBash>
#
# 数据全部读自本地会话日志,运行/刷新不联网、不改动任何 CLI(仅 --update-prices 显式联网更新价格表):
#   Claude Code: ~/.claude/projects/<proj>/<session>.jsonl  (assistant 行 message.usage,增量)
#   Codex:       ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl (token_count 事件,含额度)

import os
import sys
import glob
import json
import re
from datetime import datetime, timedelta, date

HOME = os.path.expanduser("~")
CLAUDE_DIR = os.path.join(HOME, ".claude", "projects")
CODEX_DIR = os.path.join(HOME, ".codex", "sessions")
GEMINI_DIR = os.path.join(HOME, ".gemini", "tmp")
GROK_DIR = os.path.join(HOME, ".grok", "sessions")
QODER_DIR = os.path.join(HOME, ".qoder")
HERMES_DB = os.path.join(HOME, ".hermes", "state.db")
OPENCODE_DIR = os.path.join(HOME, ".local", "share", "opencode", "storage", "message")
OPENCLAW_DB = os.path.join(HOME, ".openclaw", "tasks", "runs.sqlite")
OPENCLAW_AGENTS = os.path.join(HOME, ".openclaw", "agents")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
_USER_DIR = os.path.join(HOME, ".tokei")

def _writable_path(name):
    """优先用 ~/.tokei/ 下的可写副本,没有则用脚本同目录(开发模式)。"""
    user = os.path.join(_USER_DIR, name)
    if os.path.isfile(user):
        return user
    base = os.path.join(BASE_DIR, name)
    if os.path.isfile(base):
        if ".app/" in BASE_DIR:
            os.makedirs(_USER_DIR, exist_ok=True)
            import shutil; shutil.copy2(base, user)
            return user
        return base
    return os.path.join(_USER_DIR, name)

PRICING_FILE = _writable_path("pricing.json")
OVERRIDES_FILE = _writable_path("pricing_overrides.json")

# 每 1M token 美元单价。基准价来自 OpenRouter,外置在 pricing.json(由 --update-prices 同步);
# pricing_overrides.json 做本地修正(write1h / 别名 / 缺漏),一键更新不覆盖它。
# write5m / write1h = 5 分钟 / 1 小时 缓存写入价(OpenRouter 只给一档 cache_write=5m,
# Anthropic 的 1h 写派生为 2×输入价)。

# 内置兜底:pricing.json 缺失时仍能离线工作(口径与 OpenRouter 一致)。
_DEFAULT_PRICES = {
    "anthropic/claude-opus-4.8":     {"in": 5.0,   "out": 25.0, "cache_read": 0.5,    "cache_write": 6.25},
    "anthropic/claude-sonnet-4.6":   {"in": 3.0,   "out": 15.0, "cache_read": 0.3,    "cache_write": 3.75},
    "anthropic/claude-haiku-4.5":    {"in": 1.0,   "out": 5.0,  "cache_read": 0.1,    "cache_write": 1.25},
    "openai/gpt-5.5":                {"in": 5.0,   "out": 30.0, "cache_read": 0.5,    "cache_write": 0.0},
    "qwen/qwen3.7-max":              {"in": 1.25,  "out": 3.75, "cache_read": 0.25,   "cache_write": 1.5625},
    "deepseek/deepseek-v4-pro":      {"in": 0.435, "out": 0.87, "cache_read": 0.0036, "cache_write": 0.0},
    "google/gemini-3.5-flash":       {"in": 1.5,   "out": 9.0,  "cache_read": 0.15,   "cache_write": 0.0833},
    "google/gemini-3.1-pro-preview": {"in": 2.0,   "out": 12.0, "cache_read": 0.2,    "cache_write": 0.375},
}


def _load_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


_PRICING_DB = _load_json(PRICING_FILE, {}).get("models", {})
_OVERRIDES = _load_json(OVERRIDES_FILE, {})
_OV_MODELS = _OVERRIDES.get("models", {})
_OV_ALIASES = _OVERRIDES.get("aliases", {})

# 家族关键字 → 代表性 canonical id(精确匹配失败时回退)。
_FAMILY = [
    ("opus",     "anthropic/claude-opus-4.8"),
    ("sonnet",   "anthropic/claude-sonnet-4.6"),
    ("haiku",    "anthropic/claude-haiku-4.5"),
    ("gpt-5",    "openai/gpt-5.5"),
    ("qwen",     "qwen/qwen3.7-max"),
    ("deepseek", "deepseek/deepseek-v4-pro"),
]


def _normalize(model: str):
    """本地 model 名 → OpenRouter canonical id。免费档去 :free 按基础价;preview 后缀保留。"""
    m = (model or "").strip().lower()
    if not m or m == "<synthetic>":
        return None
    m = re.sub(r"[:\-]free$", "", m)                  # 免费档按基础价
    if "/" in m:
        return m                                      # 已是 OpenRouter 格式
    if m.startswith("claude"):
        m = re.sub(r"-(\d+)-(\d+)$", r"-\1.\2", m)    # claude-opus-4-8 → claude-opus-4.8
        return "anthropic/" + m
    if re.match(r"(gpt|o\d|chatgpt)", m):
        return "openai/" + m
    if m.startswith("gemini"):
        return "google/" + m
    if m.startswith("grok"):
        return "x-ai/" + m
    if m.startswith("qwen"):
        return "qwen/" + m
    if m.startswith("deepseek"):
        return "deepseek/" + m
    return m


def _resolve_id(model: str):
    """解析到 canonical id;未知按 opus 兜底(偏保守)。<synthetic> 返回 None。"""
    s = (model or "").strip()
    if not s or s.lower() == "<synthetic>":
        return None
    if s in _OV_ALIASES:
        return _OV_ALIASES[s]
    norm = _normalize(model)
    if norm and (norm in _OV_MODELS or norm in _PRICING_DB or norm in _DEFAULT_PRICES):
        return norm
    low = s.lower()
    if "gemini" in low:                               # gemini 版本繁多,按 pro/flash 粗分回退
        return "google/gemini-3.1-pro-preview" if "pro" in low else "google/gemini-3.5-flash"
    for kw, rep in _FAMILY:
        if kw in low:
            return rep
    return "anthropic/claude-opus-4.8"


def _raw_price(model: str):
    """统一查价 → {in,out,cache_read,cache_write,write1h?}。<synthetic>→全 0。"""
    cid = _resolve_id(model)
    if cid is None:
        return {"in": 0.0, "out": 0.0, "cache_read": 0.0, "cache_write": 0.0}
    p = dict(_DEFAULT_PRICES.get(cid, {}))            # 内置兜底打底
    p.update(_PRICING_DB.get(cid, {}))                # OpenRouter 基准
    p.update(_OV_MODELS.get(cid, {}))                 # 本地覆盖优先
    out = {"in": p.get("in", 0.0), "out": p.get("out", 0.0),
           "cache_read": p.get("cache_read", 0.0), "cache_write": p.get("cache_write", 0.0)}
    if "write1h" in p:
        out["write1h"] = p["write1h"]
    elif cid.startswith("anthropic/"):                # Anthropic 1h 写 = 2×输入价
        out["write1h"] = out["in"] * 2
    return out


def price_for(model: str):
    """Claude 成本用:补 write5m/write1h 两档(write5m = OpenRouter cache_write)。"""
    p = _raw_price(model)
    return {"in": p["in"], "out": p["out"], "cache_read": p["cache_read"],
            "write5m": p["cache_write"], "write1h": p.get("write1h", p["cache_write"])}


def gemini_price(model: str):
    """Gemini 成本用:in/out/cache_read 取统一查价(OpenRouter 已分版本,比正则更准)。"""
    return _raw_price(model)


RANGE_KEYS = ["today", "yesterday", "week", "last_week", "month", "year"]


def nice_model(m: str) -> str:
    """claude-opus-4-7 → Opus 4.7;<synthetic> → 合成;其它去前缀/-free 后美化。"""
    if not m or m == "<synthetic>":
        return "合成"
    import re
    s = m.lower()
    for key, disp in (("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku")):
        if key in s:
            mt = re.search(r"(\d+)-(\d+)", s)
            return f"{disp} {mt.group(1)}.{mt.group(2)}" if mt else disp
    name = re.sub(r"[-:](free|preview|latest)$", "", m.split("/")[-1]).replace("-", " ")
    return " ".join(w[:1].upper() + w[1:] if w[:1].isalpha() else w
                    for w in name.split())


def range_bounds():
    """返回今日/昨日/本周(周一起)/本月(1号起)/本年(1月1日起)的本地起点。"""
    now = datetime.now().astimezone()
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    yesterday = today - timedelta(days=1)
    week = today - timedelta(days=today.weekday())   # 周一 0
    last_week_start = week - timedelta(days=7)       # 上周一
    month = today.replace(day=1)
    year = today.replace(month=1, day=1)
    return {"today": today, "yesterday": yesterday, "week": week,
            "last_week": last_week_start, "last_week_end": week, "month": month, "year": year}


def classify(dt, b):
    """给定本地化 dt,返回它命中的区间 key 列表(今日同时属本周/本月/本年)。"""
    d = dt.date()
    ks = []
    if d == b["today"].date():
        ks.append("today")
    if d == b["yesterday"].date():
        ks.append("yesterday")
    if dt >= b["week"]:
        ks.append("week")
    if b["last_week"] <= dt < b["last_week_end"]:
        ks.append("last_week")
    if dt >= b["month"]:
        ks.append("month")
    if dt >= b["year"]:
        ks.append("year")
    return ks


def parse_ts(s: str):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def human(n: float) -> str:
    n = float(n)
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.0f}K"
    return f"{n:.0f}"


# ---------- 增量扫描缓存 ----------
import tempfile as _tempfile
_SCAN_CACHE_FILE = os.path.join(_tempfile.gettempdir(), "_tokei_scan_cache.json")
_SCAN_CACHE_VERSION = 3


def _load_scan_cache():
    try:
        with open(_SCAN_CACHE_FILE, "r") as f:
            c = json.load(f)
        if c.get("v") != _SCAN_CACHE_VERSION:
            return {"v": _SCAN_CACHE_VERSION}
        return c
    except Exception:
        return {"v": _SCAN_CACHE_VERSION}


def _save_scan_cache(cache):
    cache["v"] = _SCAN_CACHE_VERSION
    try:
        with open(_SCAN_CACHE_FILE, "w") as f:
            json.dump(cache, f, separators=(',', ':'))
    except Exception:
        pass


def _empty_claude():
    ranges = {k: {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0,
                  "models": {}, "sessions": set()} for k in RANGE_KEYS}
    return {"ranges": ranges, "cur": {"in": 0, "out": 0, "cr": 0, "cw": 0, "name": "-"}}


def _empty_codex():
    ranges = {k: {"in": 0, "cached": 0, "out": 0, "reason": 0,
                  "cost": 0.0, "sessions": set()} for k in RANGE_KEYS}
    return {"ranges": ranges, "limits": None, "plan": None}


def _empty_gemini():
    ranges = {k: {"in": 0, "out": 0, "cached": 0, "thoughts": 0,
                  "cost": 0.0, "models": {}, "sessions": set()} for k in RANGE_KEYS}
    return {"ranges": ranges}


def _empty_grok():
    ranges = {k: {"tokens": 0, "sessions": set(), "turns": 0, "tools": 0,
                  "duration": 0, "ctx_used": 0, "ctx_window": 0, "errors": 0,
                  "cancellations": 0, "ttft_sum": 0, "response_sum": 0, "latency_count": 0}
              for k in RANGE_KEYS}
    return {"ranges": ranges, "model": None}


def _empty_qoder():
    ranges = {k: {"in": 0, "out": 0, "sessions": 0, "calls": 0,
                  "duration": 0, "ctx_sum": 0.0, "ctx_count": 0} for k in RANGE_KEYS}
    return {"ranges": ranges, "quota": None, "model": None}


def _empty_hermes():
    ranges = {k: {"in": 0, "out": 0, "cr": 0, "cw": 0, "reason": 0,
                  "cost": 0.0, "sessions": 0, "models": {}} for k in RANGE_KEYS}
    return {"ranges": ranges}


def _empty_openclaw():
    ranges = {k: {"tasks": 0, "completed": 0, "failed": 0,
                  "in": 0, "out": 0, "cr": 0, "cw": 0,
                  "cost": 0.0, "sessions": set(), "models": {}} for k in RANGE_KEYS}
    return {"ranges": ranges}


def _empty_opencode():
    ranges = {k: {"in": 0, "out": 0, "cr": 0, "cw": 0, "reason": 0,
                  "cost": 0.0, "sessions": set(), "models": {}} for k in RANGE_KEYS}
    return {"ranges": ranges}


def _safe_scan(name, fn, fallback, errors):
    try:
        return fn()
    except Exception as e:
        errors[name] = f"{type(e).__name__}: {e}"
        return fallback()


# ---------- Claude Code ----------
def scan_claude(bounds, cache):
    fc = cache.setdefault("claude", {})
    B = {k: {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0, "models": {}, "sessions": set()}
         for k in RANGE_KEYS}
    cur_file, cur_mtime = None, -1.0
    if not os.path.isdir(CLAUDE_DIR):
        return {"ranges": B, "cur": {"in": 0, "out": 0, "cr": 0, "cw": 0, "name": "-"}}

    today_d = bounds["today"].date()
    yest_d = bounds["yesterday"].date()
    week_d = bounds["week"].date()
    lw_start_d = bounds["last_week"].date()
    lw_end_d = bounds["last_week_end"].date()
    month_d = bounds["month"].date()
    year_d = bounds["year"].date()

    stale = set(fc.keys())

    for f in glob.glob(os.path.join(CLAUDE_DIR, "*", "*.jsonl")):
        stale.discard(f)
        try:
            st = os.stat(f)
        except OSError:
            continue
        mtime, size = st.st_mtime, st.st_size
        if mtime > cur_mtime:
            cur_mtime = mtime
            cur_file = f
        sig = f"{mtime}:{size}"
        entry = fc.get(f)
        if not entry or entry.get("sig") != sig:
            days = {}
            hours = [0] * 24
            proj = None
            try:
                with open(f, "r", encoding="utf-8", errors="ignore") as fh:
                    for line in fh:
                        if '"usage"' not in line:
                            continue
                        u = _claude_usage(line, want_dt=True)
                        if not u:
                            continue
                        dt = u["dt"]
                        dk = dt.date().isoformat()
                        day = days.setdefault(dk, {"in": 0, "out": 0, "cr": 0, "cw": 0,
                                                   "cost": 0.0, "models": {}})
                        day["in"] += u["in"]; day["out"] += u["out"]
                        day["cr"] += u["cr"]; day["cw"] += u["cw"]; day["cost"] += u["cost"]
                        mm = day["models"].setdefault(
                            u["model"], {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0})
                        mm["in"] += u["in"]; mm["out"] += u["out"]
                        mm["cr"] += u["cr"]; mm["cw"] += u["cw"]; mm["cost"] += u["cost"]
                        # Wrapped 用:小时分布 / 项目 / 会话跨度
                        hours[dt.hour] += u["in"] + u["out"] + u["cr"] + u["cw"]
                        if proj is None and u.get("cwd"):
                            proj = u["cwd"]
            except OSError:
                continue
            fc[f] = {"sig": sig, "days": days, "hours": hours, "proj": proj}

    for p in stale:
        fc.pop(p, None)

    # Assembly: per-day → range buckets
    for f, entry in fc.items():
        for dk, day in entry.get("days", {}).items():
            d = date.fromisoformat(dk)
            ks = []
            if d == today_d: ks.append("today")
            if d == yest_d: ks.append("yesterday")
            if d >= week_d: ks.append("week")
            if lw_start_d <= d < lw_end_d: ks.append("last_week")
            if d >= month_d: ks.append("month")
            if d >= year_d: ks.append("year")
            if not ks:
                continue
            for k in ks:
                b = B[k]
                b["sessions"].add(f)
                b["in"] += day["in"]; b["out"] += day["out"]
                b["cr"] += day["cr"]; b["cw"] += day["cw"]; b["cost"] += day["cost"]
                for mn, mv in day["models"].items():
                    mm = b["models"].setdefault(mn, {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0})
                    mm["in"] += mv["in"]; mm["out"] += mv["out"]
                    mm["cr"] += mv["cr"]; mm["cw"] += mv["cw"]; mm["cost"] += mv["cost"]

    # Current session: sum all days of the most recently modified file
    cur_in = cur_out = cur_cr = cur_cw = 0
    if cur_file:
        entry = fc.get(cur_file)
        if entry:
            for day in entry.get("days", {}).values():
                cur_in += day["in"]; cur_out += day["out"]
                cur_cr += day["cr"]; cur_cw += day["cw"]

    return {
        "ranges": B,
        "cur": {"in": cur_in, "out": cur_out, "cr": cur_cr, "cw": cur_cw,
                "name": os.path.basename(cur_file)[:8] if cur_file else "-"},
    }


def _claude_usage(line, want_dt=False):
    try:
        o = json.loads(line)
    except Exception:
        return None
    if o.get("type") != "assistant":
        return None
    dt = None
    if want_dt:
        # timestamp 是 UTC,转本地用于区间归类
        dt = parse_ts(o.get("timestamp", ""))
        if dt is None:
            return None
        dt = dt.astimezone()
    msg = o.get("message", {})
    u = msg.get("usage")
    if not u:
        return None
    inp = u.get("input_tokens", 0) or 0
    out = u.get("output_tokens", 0) or 0
    cr = u.get("cache_read_input_tokens", 0) or 0
    cw = u.get("cache_creation_input_tokens", 0) or 0
    p = price_for(msg.get("model"))
    cc = u.get("cache_creation") or {}
    w5 = cc.get("ephemeral_5m_input_tokens")
    w1 = cc.get("ephemeral_1h_input_tokens")
    if w5 is None and w1 is None:
        write_cost = cw / 1e6 * p["write5m"]
    else:
        write_cost = (w5 or 0) / 1e6 * p["write5m"] + (w1 or 0) / 1e6 * p["write1h"]
    cost = inp / 1e6 * p["in"] + out / 1e6 * p["out"] + cr / 1e6 * p["cache_read"] + write_cost
    res = {"in": inp, "out": out, "cr": cr, "cw": cw, "cost": cost,
           "model": msg.get("model"), "cwd": o.get("cwd")}
    if want_dt:
        res["dt"] = dt
    return res


# ---------- Codex ----------
def scan_codex(bounds, cache):
    fc = cache.setdefault("codex", {})
    B = {k: {"in": 0, "cached": 0, "out": 0, "reason": 0, "cost": 0.0, "sessions": set()}
         for k in RANGE_KEYS}
    cx_base = _raw_price("openai/gpt-5.5")
    if not os.path.isdir(CODEX_DIR):
        return {"ranges": B, "cur_total": None, "limits": None, "plan": None}

    today_d = bounds["today"].date()
    yest_d = bounds["yesterday"].date()
    week_d = bounds["week"].date()
    lw_start_d = bounds["last_week"].date()
    lw_end_d = bounds["last_week_end"].date()
    month_d = bounds["month"].date()
    year_d = bounds["year"].date()

    cur_file, cur_mtime = None, -1.0
    stale = set(fc.keys())

    for f in glob.glob(os.path.join(CODEX_DIR, "**", "rollout-*.jsonl"), recursive=True):
        stale.discard(f)
        try:
            st = os.stat(f)
        except OSError:
            continue
        mtime, size = st.st_mtime, st.st_size
        if mtime > cur_mtime:
            cur_mtime = mtime
            cur_file = f
        sig = f"{mtime}:{size}"
        entry = fc.get(f)
        if not entry or entry.get("sig") != sig:
            days = {}
            file_limits = None; file_limits_ts = None; file_plan = None
            file_g_limits = None; file_g_ts = None; file_g_plan = None
            file_last_total = None
            try:
                with open(f, "r", encoding="utf-8", errors="ignore") as fh:
                    for line in fh:
                        if '"token_count"' not in line:
                            continue
                        try:
                            o = json.loads(line)
                        except Exception:
                            continue
                        info = (o.get("payload") or {}).get("info") or {}
                        last = info.get("last_token_usage") or {}
                        total = info.get("total_token_usage") or {}
                        if total:
                            file_last_total = total
                        ts = parse_ts(o.get("timestamp", ""))
                        rl = (o.get("payload") or {}).get("rate_limits")
                        if ts and rl:
                            ts_iso = ts.isoformat()
                            if file_g_ts is None or ts_iso > file_g_ts:
                                file_g_ts = ts_iso
                                file_g_limits = rl
                                file_g_plan = rl.get("plan_type")
                            if rl.get("limit_id") == "codex" and (file_limits_ts is None or ts_iso > file_limits_ts):
                                file_limits_ts = ts_iso
                                file_limits = rl
                                file_plan = rl.get("plan_type")
                        if ts and last:
                            dk = ts.astimezone().date().isoformat()
                            li = last.get("input_tokens", 0) or 0
                            lc = last.get("cached_input_tokens", 0) or 0
                            lo = last.get("output_tokens", 0) or 0
                            lr = last.get("reasoning_output_tokens", 0) or 0
                            hi = li > 272_000
                            p_in = cx_base["in"] * (2 if hi else 1)
                            p_out = cx_base["out"] * (1.5 if hi else 1)
                            p_cr = cx_base["cache_read"] * (2 if hi else 1)
                            cost = (li - lc) / 1e6 * p_in + lc / 1e6 * p_cr + lo / 1e6 * p_out
                            day = days.setdefault(dk, {"in": 0, "cached": 0, "out": 0,
                                                       "reason": 0, "cost": 0.0})
                            day["in"] += li; day["cached"] += lc
                            day["out"] += lo; day["reason"] += lr; day["cost"] += cost
            except OSError:
                continue
            fc[f] = {"sig": sig, "days": days,
                     "limits": file_limits, "limits_ts": file_limits_ts, "plan": file_plan,
                     "g_limits": file_g_limits, "g_ts": file_g_ts, "g_plan": file_g_plan,
                     "last_total": file_last_total}

    for p in stale:
        fc.pop(p, None)

    # Assembly: per-day → range buckets
    for f, entry in fc.items():
        for dk, day in entry.get("days", {}).items():
            d = date.fromisoformat(dk)
            ks = []
            if d == today_d: ks.append("today")
            if d == yest_d: ks.append("yesterday")
            if d >= week_d: ks.append("week")
            if lw_start_d <= d < lw_end_d: ks.append("last_week")
            if d >= month_d: ks.append("month")
            if d >= year_d: ks.append("year")
            if not ks:
                continue
            for k in ks:
                b = B[k]
                b["sessions"].add(f)
                b["in"] += day["in"]; b["cached"] += day["cached"]
                b["out"] += day["out"]; b["reason"] += day["reason"]; b["cost"] += day["cost"]

    # Find latest limits across all cached files
    latest_limits = None; latest_ts = None; plan_type = None
    g_limits = None; g_ts = None
    for entry in fc.values():
        if entry.get("limits_ts"):
            if latest_ts is None or entry["limits_ts"] > latest_ts:
                latest_ts = entry["limits_ts"]
                latest_limits = entry["limits"]
                plan_type = entry["plan"]
        if entry.get("g_ts"):
            if g_ts is None or entry["g_ts"] > g_ts:
                g_ts = entry["g_ts"]
                g_limits = entry["g_limits"]

    if latest_limits is None and g_limits is not None:
        latest_limits = g_limits
        plan_type = (g_limits or {}).get("plan_type")

    cur_total = None
    if cur_file:
        entry = fc.get(cur_file)
        if entry:
            cur_total = entry.get("last_total")

    return {
        "ranges": B,
        "cur_total": cur_total,
        "limits": latest_limits,
        "plan": plan_type,
    }


# ---------- Gemini CLI ----------
# 日志:~/.gemini/tmp/<projectHash>/chats/session-*.json
# assistant 行 type=="gemini",tokens={input,output,cached,thoughts,total}
# (total=input+output+thoughts,cached⊂input)。增量快照共用 sessionId,按 lastUpdated 去重。
def scan_gemini(bounds):
    if not os.path.isdir(GEMINI_DIR):
        return _empty_gemini()
    scan_from = min(bounds["yesterday"], bounds["week"], bounds["month"], bounds["year"]).timestamp()
    best = {}  # sessionId -> (lastUpdated, data),同 id 取最新快照
    for f in glob.glob(os.path.join(GEMINI_DIR, "*", "chats", "session-*.json")):
        try:
            if os.path.getmtime(f) < scan_from:
                continue
        except OSError:
            continue
        try:
            with open(f, "r", encoding="utf-8", errors="ignore") as fh:
                d = json.load(fh)
        except Exception:
            continue
        sid = d.get("sessionId") or f
        lu = d.get("lastUpdated") or ""
        if sid not in best or lu > best[sid][0]:
            best[sid] = (lu, d)

    B = {k: {"in": 0, "out": 0, "cached": 0, "thoughts": 0, "cost": 0.0,
             "models": {}, "sessions": set()}
         for k in RANGE_KEYS}
    for sid, (lu, d) in best.items():
        for m in d.get("messages", []):
            if m.get("type") != "gemini":
                continue
            tk = m.get("tokens")
            if not tk:
                continue
            dt = parse_ts(m.get("timestamp", ""))
            if dt is None:
                continue
            ks = classify(dt.astimezone(), bounds)
            if not ks:
                continue
            model = m.get("model")
            inp = tk.get("input", 0) or 0
            out = tk.get("output", 0) or 0
            cached = tk.get("cached", 0) or 0
            th = tk.get("thoughts", 0) or 0
            p = gemini_price(model)
            cost = (max(inp - cached, 0) / 1e6 * p["in"]
                    + cached / 1e6 * p["cache_read"]
                    + (out + th) / 1e6 * p["out"])
            for k in ks:
                b = B[k]
                b["sessions"].add(sid)
                b["in"] += inp; b["out"] += out
                b["cached"] += cached; b["thoughts"] += th; b["cost"] += cost
                mm = b["models"].setdefault(
                    model, {"in": 0, "out": 0, "cached": 0, "thoughts": 0, "cost": 0.0})
                mm["in"] += inp; mm["out"] += out
                mm["cached"] += cached; mm["thoughts"] += th; mm["cost"] += cost
    return {"ranges": B}


# ---------- Grok CLI ----------
# 日志:~/.grok/sessions/<cwd>/<uuid>/{summary.json,signals.json,events.jsonl,updates.jsonl}
# 当前 Grok CLI 本地日志未落 prompt_tokens/completion_tokens usage;官方 API 响应有 usage。
# 这里展示 Grok 本地可验证的上下文、轮次、工具、耗时和延迟,不估真实消耗成本。
def scan_grok(bounds):
    B = {k: {"tokens": 0, "sessions": set(), "turns": 0, "tools": 0,
             "duration": 0, "ctx_used": 0, "ctx_window": 0, "errors": 0,
             "cancellations": 0, "ttft_sum": 0, "response_sum": 0, "latency_count": 0}
         for k in RANGE_KEYS}
    latest_mtime = -1.0
    latest_model = None
    if not os.path.isdir(GROK_DIR):
        return {"ranges": B, "model": None}
    for sm in glob.glob(os.path.join(GROK_DIR, "*", "*", "summary.json")):
        try:
            mtime = os.path.getmtime(sm)
        except OSError:
            continue
        try:
            with open(sm, "r", encoding="utf-8", errors="ignore") as fh:
                s = json.load(fh)
        except Exception:
            continue
        if mtime > latest_mtime:
            latest_mtime = mtime
            latest_model = s.get("current_model_id")
        dt = parse_ts(s.get("updated_at") or s.get("created_at") or "")
        if dt is None:
            continue
        ks = classify(dt.astimezone(), bounds)
        if not ks:
            continue
        sig = {}
        sj = os.path.join(os.path.dirname(sm), "signals.json")
        try:
            with open(sj, "r", encoding="utf-8", errors="ignore") as fh:
                sig = json.load(fh)
        except Exception:
            sig = {}

        mx = 0
        uj = os.path.join(os.path.dirname(sm), "updates.jsonl")
        try:
            with open(uj, "r", encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    if "totalTokens" not in line:
                        continue
                    try:
                        o = json.loads(line)
                    except Exception:
                        continue
                    tt = (((o.get("params") or {}).get("_meta") or {}).get("totalTokens"))
                    if isinstance(tt, (int, float)) and tt > mx:
                        mx = int(tt)
        except OSError:
            pass

        event_turns = event_tools = event_duration = event_errors = event_cancellations = 0
        ej = os.path.join(os.path.dirname(sm), "events.jsonl")
        try:
            with open(ej, "r", encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    try:
                        e = json.loads(line)
                    except Exception:
                        continue
                    typ = e.get("type")
                    if typ == "turn_started":
                        event_turns += 1
                    elif typ == "tool_completed":
                        event_tools += 1
                        event_duration += int(e.get("duration_ms") or 0)
                        if e.get("outcome") not in (None, "success"):
                            event_errors += 1
                    elif typ == "turn_ended" and e.get("outcome") not in (None, "completed"):
                        event_cancellations += 1
        except OSError:
            pass

        turns = int(sig.get("turnCount") or event_turns or 0)
        tools = int(sig.get("toolCallCount") or event_tools or 0)
        duration = int(sig.get("sessionDurationSeconds") or 0)
        ctx_used = int(sig.get("contextTokensUsed") or mx or 0)
        ctx_window = int(sig.get("contextWindowTokens") or 0)
        errors = int(sig.get("errorCount") or 0) + int(sig.get("toolFailureCount") or event_errors or 0)
        cancellations = int(sig.get("cancellationCount") or event_cancellations or 0)
        latency_count = int(sig.get("latencySampleCount") or turns or 0)
        ttft_sum = int(sig.get("avgTimeToFirstTokenMs") or 0) * latency_count
        response_sum = int(sig.get("avgResponseTimeMs") or 0) * latency_count
        token_proxy = ctx_used or mx

        sid = (s.get("info") or {}).get("id") or sm
        for k in ks:
            b = B[k]
            b["tokens"] += token_proxy
            b["sessions"].add(sid)
            b["turns"] += turns
            b["tools"] += tools
            b["duration"] += duration
            b["ctx_used"] += ctx_used
            b["ctx_window"] += ctx_window
            b["errors"] += errors
            b["cancellations"] += cancellations
            b["ttft_sum"] += ttft_sum
            b["response_sum"] += response_sum
            b["latency_count"] += latency_count
    return {"ranges": B, "model": latest_model}


# ---------- Qoder ----------
# QoderWork SQLite:~/Library/Application Support/QoderWork/data/agents.db
# messages 表 metadata 含 durationMs / contextUsageRatio(token 字段目前全 0)。
_QODER_DB = os.path.join(HOME, "Library", "Application Support", "QoderWork", "data", "agents.db")


def scan_qoder(bounds, cache):
    import sqlite3 as _sqlite3
    fc = cache.setdefault("qoder", {})
    empty = {k: {"in": 0, "out": 0, "sessions": 0, "calls": 0,
                 "duration": 0, "ctx_sum": 0.0, "ctx_count": 0}
             for k in RANGE_KEYS}
    if not os.path.isfile(_QODER_DB):
        return {"ranges": empty}

    try:
        sig = f"{os.path.getmtime(_QODER_DB)}:{os.path.getsize(_QODER_DB)}"
    except OSError:
        return {"ranges": empty}

    entry = fc.get("db")
    if not entry or entry.get("sig") != sig:
        days = {}
        try:
            conn = _sqlite3.connect(f"file:{_QODER_DB}?mode=ro", uri=True)
            for row in conn.execute("""
                SELECT date(created_at,'unixepoch','localtime') as day,
                       COUNT(*) as calls,
                       COUNT(DISTINCT chat_id) as sessions,
                       COALESCE(SUM(json_extract(metadata,'$.inputTokens')),0),
                       COALESCE(SUM(json_extract(metadata,'$.outputTokens')),0),
                       COALESCE(SUM(json_extract(metadata,'$.durationMs')),0),
                       COALESCE(AVG(CASE WHEN json_extract(metadata,'$.contextUsageRatio')>0
                                    THEN json_extract(metadata,'$.contextUsageRatio') END),0)
                FROM messages WHERE metadata!='{}'
                GROUP BY day
            """):
                dk, calls, sessions, ti, to_, dur, ctx = row
                if dk:
                    days[dk] = {"calls": calls, "sessions": sessions,
                                "in": int(ti or 0), "out": int(to_ or 0),
                                "duration": int(dur or 0), "ctx_ratio": float(ctx or 0)}
            conn.close()
        except Exception:
            pass
        fc["db"] = {"sig": sig, "days": days}
        entry = fc["db"]

    today_d = bounds["today"].date()
    yest_d = bounds["yesterday"].date()
    week_d = bounds["week"].date()
    lw_start_d = bounds["last_week"].date()
    lw_end_d = bounds["last_week_end"].date()
    month_d = bounds["month"].date()
    year_d = bounds["year"].date()

    B = {k: {"in": 0, "out": 0, "sessions": 0, "calls": 0,
             "duration": 0, "ctx_sum": 0.0, "ctx_count": 0}
         for k in RANGE_KEYS}

    for dk, day in entry.get("days", {}).items():
        try:
            d = date.fromisoformat(dk)
        except ValueError:
            continue
        ks = []
        if d == today_d: ks.append("today")
        if d == yest_d: ks.append("yesterday")
        if d >= week_d: ks.append("week")
        if lw_start_d <= d < lw_end_d: ks.append("last_week")
        if d >= month_d: ks.append("month")
        if d >= year_d: ks.append("year")
        for k in ks:
            b = B[k]
            b["in"] += day["in"]; b["out"] += day["out"]
            b["sessions"] += day["sessions"]; b["calls"] += day["calls"]
            b["duration"] += day["duration"]
            if day["ctx_ratio"] > 0:
                b["ctx_sum"] += day["ctx_ratio"] * day["calls"]
                b["ctx_count"] += day["calls"]

    # 从 QoderWork 日志提取最新 credit 额度
    quota = None
    qw_logs = os.path.join(HOME, "Library", "Application Support", "QoderWork", "logs")
    if os.path.isdir(qw_logs):
        log_dirs = sorted(glob.glob(os.path.join(qw_logs, "2*")), reverse=True)
        for ld in log_dirs[:2]:
            main_log = os.path.join(ld, "main.log")
            if not os.path.isfile(main_log):
                continue
            try:
                with open(main_log, "r", encoding="utf-8", errors="ignore") as fh:
                    for line in fh:
                        if '"operation":"usage"' not in line or '"userQuota"' not in line:
                            continue
                        m = re.search(r'"data":(\{.*?"isQuotaExceeded":\w+)', line)
                        if not m:
                            continue
                        try:
                            quota = json.loads(m.group(1) + "}")
                        except Exception:
                            pass
            except OSError:
                pass
            if quota:
                break

    # 当前模型
    model = None
    try:
        import sqlite3 as _sq
        conn = _sq.connect(f"file:{_QODER_DB}?mode=ro", uri=True)
        row = conn.execute("SELECT value FROM app_settings WHERE key='modelLevel'").fetchone()
        if row:
            model = row[0].strip('"')
        conn.close()
    except Exception:
        pass

    return {"ranges": B, "quota": quota, "model": model}


# ---------- Hermes ----------
# SQLite: ~/.hermes/state.db sessions 表,完整 token + cost 数据。
def scan_hermes(bounds, cache):
    import sqlite3 as _sq
    fc = cache.setdefault("hermes", {})
    empty = {k: {"in": 0, "out": 0, "cr": 0, "cw": 0, "reason": 0, "cost": 0.0,
                 "sessions": 0, "models": {}} for k in RANGE_KEYS}
    if not os.path.isfile(HERMES_DB):
        return {"ranges": empty}
    try:
        sig = f"{os.path.getmtime(HERMES_DB)}:{os.path.getsize(HERMES_DB)}"
    except OSError:
        return {"ranges": empty}
    entry = fc.get("db")
    if not entry or entry.get("sig") != sig:
        days = {}
        try:
            conn = _sq.connect(f"file:{HERMES_DB}?mode=ro", uri=True)
            for row in conn.execute("""
                SELECT date(started_at,'unixepoch','localtime') as day,
                       COUNT(*) as cnt, model,
                       COALESCE(SUM(input_tokens),0),
                       COALESCE(SUM(output_tokens),0),
                       COALESCE(SUM(cache_read_tokens),0),
                       COALESCE(SUM(cache_write_tokens),0),
                       COALESCE(SUM(reasoning_tokens),0),
                       COALESCE(SUM(COALESCE(actual_cost_usd,estimated_cost_usd)),0)
                FROM sessions WHERE started_at > 0
                GROUP BY day, model
            """):
                dk, cnt, model, ti, to_, cr, cw, reason, cost = row
                if not dk:
                    continue
                day = days.setdefault(dk, {"in": 0, "out": 0, "cr": 0, "cw": 0,
                                           "reason": 0, "cost": 0.0, "sessions": 0, "models": {}})
                day["in"] += int(ti); day["out"] += int(to_)
                day["cr"] += int(cr); day["cw"] += int(cw)
                day["reason"] += int(reason); day["cost"] += float(cost)
                day["sessions"] += int(cnt)
                if model:
                    mm = day["models"].setdefault(model, {"in": 0, "out": 0, "cost": 0.0})
                    mm["in"] += int(ti); mm["out"] += int(to_); mm["cost"] += float(cost)
            conn.close()
        except Exception:
            pass
        fc["db"] = {"sig": sig, "days": days}
        entry = fc["db"]

    today_d = bounds["today"].date()
    yest_d = bounds["yesterday"].date()
    week_d = bounds["week"].date()
    month_d = bounds["month"].date()
    year_d = bounds["year"].date()

    B = {k: {"in": 0, "out": 0, "cr": 0, "cw": 0, "reason": 0, "cost": 0.0,
             "sessions": 0, "models": {}} for k in RANGE_KEYS}
    for dk, day in entry.get("days", {}).items():
        try:
            d = date.fromisoformat(dk)
        except ValueError:
            continue
        ks = []
        if d == today_d: ks.append("today")
        if d == yest_d: ks.append("yesterday")
        if d >= week_d: ks.append("week")
        if d >= month_d: ks.append("month")
        if d >= year_d: ks.append("year")
        for k in ks:
            b = B[k]
            b["in"] += day["in"]; b["out"] += day["out"]
            b["cr"] += day["cr"]; b["cw"] += day["cw"]
            b["reason"] += day["reason"]; b["cost"] += day["cost"]
            b["sessions"] += day["sessions"]
            for mn, mv in day.get("models", {}).items():
                mm = b["models"].setdefault(mn, {"in": 0, "out": 0, "cost": 0.0})
                mm["in"] += mv["in"]; mm["out"] += mv["out"]; mm["cost"] += mv["cost"]
    return {"ranges": B}


# ---------- OpenClaw ----------
# SQLite: ~/.openclaw/tasks/runs.sqlite — 任务计数
# Session JSONL: ~/.openclaw/agents/*/sessions/*.jsonl — token 用量
def scan_openclaw(bounds, cache):
    import sqlite3 as _sq
    fc = cache.setdefault("openclaw", {})

    today_d = bounds["today"].date()
    yest_d = bounds["yesterday"].date()
    week_d = bounds["week"].date()
    lw_start_d = bounds["last_week"].date()
    lw_end_d = bounds["last_week_end"].date()
    month_d = bounds["month"].date()
    year_d = bounds["year"].date()

    def _day_keys(d):
        ks = []
        if d == today_d: ks.append("today")
        if d == yest_d: ks.append("yesterday")
        if d >= week_d: ks.append("week")
        if lw_start_d <= d < lw_end_d: ks.append("last_week")
        if d >= month_d: ks.append("month")
        if d >= year_d: ks.append("year")
        return ks

    B = {k: {"tasks": 0, "completed": 0, "failed": 0,
             "in": 0, "out": 0, "cr": 0, "cw": 0,
             "cost": 0.0, "sessions": set(), "models": {}} for k in RANGE_KEYS}

    # --- Part 1: SQLite task counts ---
    if os.path.isfile(OPENCLAW_DB):
        try:
            sig = f"{os.path.getmtime(OPENCLAW_DB)}:{os.path.getsize(OPENCLAW_DB)}"
        except OSError:
            sig = None
        if sig:
            entry = fc.get("_db")
            if not entry or entry.get("sig") != sig:
                task_days = {}
                try:
                    conn = _sq.connect(f"file:{OPENCLAW_DB}?mode=ro", uri=True)
                    for row in conn.execute("""
                        SELECT date(created_at/1000,'unixepoch','localtime') as day,
                               COUNT(*) as total,
                               SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END),
                               SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END)
                        FROM task_runs WHERE created_at > 0
                        GROUP BY day
                    """):
                        dk, total, completed, failed = row
                        if dk:
                            task_days[dk] = {"tasks": int(total or 0), "completed": int(completed or 0),
                                             "failed": int(failed or 0)}
                    conn.close()
                except Exception:
                    pass
                fc["_db"] = {"sig": sig, "days": task_days}
            for dk, day in fc.get("_db", {}).get("days", {}).items():
                try:
                    d = date.fromisoformat(dk)
                except ValueError:
                    continue
                for k in _day_keys(d):
                    b = B[k]
                    b["tasks"] += day["tasks"]; b["completed"] += day["completed"]
                    b["failed"] += day["failed"]

    # --- Part 2: Session JSONL token usage ---
    if os.path.isdir(OPENCLAW_AGENTS):
        stale = {k for k in fc if not k.startswith("_")}
        for f in glob.glob(os.path.join(OPENCLAW_AGENTS, "*", "sessions", "*.jsonl")):
            if f.endswith(".trajectory.jsonl"):
                continue
            stale.discard(f)
            try:
                st = os.stat(f)
            except OSError:
                continue
            sig = f"{st.st_mtime}:{st.st_size}"
            entry = fc.get(f)
            if not entry or entry.get("sig") != sig:
                days = {}
                try:
                    with open(f, "r", encoding="utf-8", errors="ignore") as fh:
                        for line in fh:
                            if '"usage"' not in line:
                                continue
                            try:
                                o = json.loads(line)
                            except Exception:
                                continue
                            msg = o.get("message", {})
                            if msg.get("role") != "assistant":
                                continue
                            u = msg.get("usage")
                            if not u:
                                continue
                            dt = parse_ts(o.get("timestamp", ""))
                            if dt is None:
                                continue
                            dt = dt.astimezone()
                            inp = u.get("input", 0) or 0
                            out = u.get("output", 0) or 0
                            cr = u.get("cacheRead", 0) or 0
                            cw = u.get("cacheWrite", 0) or 0
                            if inp == 0 and out == 0:
                                continue
                            model = msg.get("model", "")
                            cid = _resolve_id(model)
                            cost_obj = u.get("cost")
                            raw_cost = float((cost_obj or {}).get("total", 0) or 0)
                            if raw_cost > 0:
                                cost = raw_cost
                            elif cid:
                                p = _raw_price(model)
                                cost = inp / 1e6 * p["in"] + out / 1e6 * p["out"] + cr / 1e6 * p["cache_read"] + cw / 1e6 * p["cache_write"]
                            else:
                                cost = 0.0
                            dk = dt.date().isoformat()
                            day = days.setdefault(dk, {"in": 0, "out": 0, "cr": 0, "cw": 0,
                                                       "cost": 0.0, "models": {}})
                            day["in"] += inp; day["out"] += out
                            day["cr"] += cr; day["cw"] += cw; day["cost"] += cost
                            mn = cid or model or "unknown"
                            mm = day["models"].setdefault(mn, {"in": 0, "out": 0, "cost": 0.0})
                            mm["in"] += inp; mm["out"] += out; mm["cost"] += cost
                except OSError:
                    continue
                fc[f] = {"sig": sig, "days": days}

        for p in stale:
            fc.pop(p, None)

        for f, entry in fc.items():
            if f.startswith("_"):
                continue
            for dk, day in entry.get("days", {}).items():
                try:
                    d = date.fromisoformat(dk)
                except ValueError:
                    continue
                for k in _day_keys(d):
                    b = B[k]
                    b["sessions"].add(f)
                    b["in"] += day["in"]; b["out"] += day["out"]
                    b["cr"] += day["cr"]; b["cw"] += day["cw"]; b["cost"] += day["cost"]
                    for mn, mv in day["models"].items():
                        mm = b["models"].setdefault(mn, {"in": 0, "out": 0, "cost": 0.0})
                        mm["in"] += mv["in"]; mm["out"] += mv["out"]; mm["cost"] += mv["cost"]

    return {"ranges": B}


# ---------- OpenCode ----------
# JSON 文件: ~/.local/share/opencode/storage/message/<session>/msg_*.json
# 每条 assistant 消息有 tokens{input,output,reasoning,cache{read,write}} + cost + modelID。
def scan_opencode(bounds, cache):
    fc = cache.setdefault("opencode", {})
    B = {k: {"in": 0, "out": 0, "cr": 0, "cw": 0, "reason": 0, "cost": 0.0,
             "sessions": set(), "models": {}} for k in RANGE_KEYS}
    if not os.path.isdir(OPENCODE_DIR):
        return {"ranges": B}

    today_d = bounds["today"].date()
    yest_d = bounds["yesterday"].date()
    week_d = bounds["week"].date()
    month_d = bounds["month"].date()
    year_d = bounds["year"].date()

    stale = set(fc.keys())

    for sess_dir in glob.glob(os.path.join(OPENCODE_DIR, "ses_*")):
        for f in glob.glob(os.path.join(sess_dir, "msg_*.json")):
            stale.discard(f)
            try:
                st = os.stat(f)
            except OSError:
                continue
            sig = f"{st.st_mtime}:{st.st_size}"
            entry = fc.get(f)
            if entry and entry.get("sig") == sig:
                day_data = entry.get("day")
            else:
                try:
                    d = json.load(open(f, encoding="utf-8"))
                except Exception:
                    continue
                if d.get("role") != "assistant":
                    fc[f] = {"sig": sig, "day": None}
                    continue
                t = (d.get("time") or {}).get("created", 0)
                if not t:
                    fc[f] = {"sig": sig, "day": None}
                    continue
                tok = d.get("tokens") or {}
                ca = tok.get("cache") or {}
                model = d.get("modelID", "")
                day_data = {
                    "date": datetime.fromtimestamp(t / 1000).strftime("%Y-%m-%d"),
                    "in": tok.get("input", 0) or 0,
                    "out": tok.get("output", 0) or 0,
                    "reason": tok.get("reasoning", 0) or 0,
                    "cr": ca.get("read", 0) or 0,
                    "cw": ca.get("write", 0) or 0,
                    "cost": d.get("cost", 0) or 0,
                    "session": d.get("sessionID", ""),
                    "model": model,
                }
                fc[f] = {"sig": sig, "day": day_data}

            if not day_data:
                continue
            try:
                dd = date.fromisoformat(day_data["date"])
            except ValueError:
                continue
            ks = []
            if dd == today_d: ks.append("today")
            if dd == yest_d: ks.append("yesterday")
            if dd >= week_d: ks.append("week")
            if dd >= month_d: ks.append("month")
            if dd >= year_d: ks.append("year")
            for k in ks:
                b = B[k]
                b["in"] += day_data["in"]; b["out"] += day_data["out"]
                b["cr"] += day_data["cr"]; b["cw"] += day_data["cw"]
                b["reason"] += day_data["reason"]; b["cost"] += day_data["cost"]
                b["sessions"].add(day_data["session"])
                mn = day_data["model"]
                if mn:
                    mm = b["models"].setdefault(mn, {"in": 0, "out": 0, "cost": 0.0})
                    mm["in"] += day_data["in"]; mm["out"] += day_data["out"]
                    mm["cost"] += day_data["cost"]

    for p in stale:
        fc.pop(p, None)
    return {"ranges": B}


def fmt_reset(epoch):
    try:
        return datetime.fromtimestamp(int(epoch)).astimezone().strftime("%m-%d %H:%M")
    except Exception:
        return "?"


# ---------- Claude 套餐用量(读 Claude Desktop 的 Chromium HTTP 缓存) ----------
# 数据来自桌面应用每 ~10min 轮询 /usage 的响应(zstd 压缩),纯本地只读。
CLAUDE_CACHE = os.path.join(
    HOME, "Library", "Application Support", "Claude", "Cache", "Cache_Data"
)


def _iso_to_epoch(s):
    dt = parse_ts(s) if s else None
    return int(dt.timestamp()) if dt else None


def _scan_claude_plan_raw():
    import shutil
    import subprocess
    import tempfile
    if not os.path.isdir(CLAUDE_CACHE) or not shutil.which("zstd"):
        return None
    # 找到缓存了 organizations/<org>/usage 的文件(文件名是 hash,按内容定位)
    cand = None
    for f in glob.glob(os.path.join(CLAUDE_CACHE, "*_0")):
        try:
            data = open(f, "rb").read()
        except OSError:
            continue
        if b"organizations/" in data and b"/usage" in data and b"\x28\xb5\x2f\xfd" in data:
            mt = os.path.getmtime(f)
            if cand is None or mt > cand[0]:
                cand = (mt, data)
    if cand is None:
        return None
    data = cand[1]
    i = data.find(b"\x28\xb5\x2f\xfd")  # zstd magic
    if i < 0:
        return None
    tmp = os.path.join(tempfile.gettempdir(), "_tokei_claude.zst")
    try:
        with open(tmp, "wb") as fh:
            fh.write(data[i:])
        raw = subprocess.run(["zstd", "-dc", tmp], capture_output=True).stdout
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass
    try:
        j = json.loads(raw)
    except Exception:
        return None
    fh_ = j.get("five_hour") or {}
    sd = j.get("seven_day") or {}
    return {
        "q5": fh_.get("utilization"),
        "q5_reset": _iso_to_epoch(fh_.get("resets_at")),
        "q7": sd.get("utilization"),
        "q7_reset": _iso_to_epoch(sd.get("resets_at")),
    }


# Claude 额度只存在 Claude Desktop 的易失缓存条目里,缓存被淘汰/重写的瞬间会读不到。
# 成功时落盘一份,失败时回退到最近一次有效值(30 分钟内,避免跨 reset 显示陈旧)。
_QUOTA_FALLBACK_TTL = 1800

def scan_claude_plan():
    import tempfile
    import time
    cache = os.path.join(tempfile.gettempdir(), "_tokei_claude_quota.json")
    r = _scan_claude_plan_raw()
    if r and r.get("q5") is not None:
        try:
            with open(cache, "w") as fh:
                json.dump({"t": time.time(), "v": r}, fh)
        except OSError:
            pass
        return r
    try:
        with open(cache) as fh:
            c = json.load(fh)
        if time.time() - c["t"] < _QUOTA_FALLBACK_TTL:
            return c["v"]
    except Exception:
        pass
    return r


def compute():
    bounds = range_bounds()
    cache = _load_scan_cache()
    errors = {}
    cc = _safe_scan("claude", lambda: scan_claude(bounds, cache), _empty_claude, errors)
    cx = _safe_scan("codex", lambda: scan_codex(bounds, cache), _empty_codex, errors)
    gm = _safe_scan("gemini", lambda: scan_gemini(bounds), _empty_gemini, errors)
    gk = _safe_scan("grok", lambda: scan_grok(bounds), _empty_grok, errors)
    qd = _safe_scan("qoder", lambda: scan_qoder(bounds, cache), _empty_qoder, errors)
    hm = _safe_scan("hermes", lambda: scan_hermes(bounds, cache), _empty_hermes, errors)
    oc = _safe_scan("openclaw", lambda: scan_openclaw(bounds, cache), _empty_openclaw, errors)
    ocode = _safe_scan("opencode", lambda: scan_opencode(bounds, cache), _empty_opencode, errors)
    _save_scan_cache(cache)

    def claude_range(b):
        denom = b["cr"] + b["cw"] + b["in"]
        hit = (b["cr"] / denom * 100) if denom else 0.0
        models = []
        for n, v in sorted(b["models"].items(), key=lambda kv: -kv[1]["cost"]):
            p = price_for(n)
            models.append({"name": nice_model(n), "in": v["in"], "out": v["out"],
                           "cr": v["cr"], "cw": v["cw"], "cost": v["cost"],
                           "pin": p["in"], "pout": p["out"]})
        return {"hit": hit, "in": b["in"], "out": b["out"],
                "cr": b["cr"], "cw": b["cw"], "cost": b["cost"], "models": models,
                "sessions": len(b["sessions"])}

    def codex_range(b):
        hit = (b["cached"] / b["in"] * 100) if b["in"] else 0.0
        return {"hit": hit, "in": b["in"] - b["cached"], "cached": b["cached"],
                "out": b["out"], "reason": b["reason"], "cost": b["cost"],
                "sessions": len(b["sessions"])}

    def gemini_range(b):
        # tokens.input 含 cached,展示口径与 Codex 一致:输入=非缓存部分
        hit = (b["cached"] / b["in"] * 100) if b["in"] else 0.0
        models = []
        for n, v in sorted(b["models"].items(), key=lambda kv: -kv[1]["cost"]):
            p = gemini_price(n)
            models.append({"name": nice_model(n), "in": max(v["in"] - v["cached"], 0),
                           "out": v["out"], "cached": v["cached"], "thoughts": v["thoughts"],
                           "cost": v["cost"], "pin": p["in"], "pout": p["out"]})
        return {"hit": hit, "in": max(b["in"] - b["cached"], 0), "out": b["out"],
                "cached": b["cached"], "thoughts": b["thoughts"], "cost": b["cost"],
                "models": models, "sessions": len(b["sessions"])}

    def grok_range(b):
        latency_count = b.get("latency_count", 0)
        ctx_window = b.get("ctx_window", 0)
        ctx_pct = (b.get("ctx_used", 0) / ctx_window * 100) if ctx_window else 0.0
        return {"tokens": b.get("tokens", 0), "sessions": len(b.get("sessions", [])),
                "turns": b.get("turns", 0), "tools": b.get("tools", 0),
                "duration": b.get("duration", 0), "ctx_used": b.get("ctx_used", 0),
                "ctx_window": ctx_window, "ctx": ctx_pct,
                "errors": b.get("errors", 0), "cancellations": b.get("cancellations", 0),
                "ttft": int(b.get("ttft_sum", 0) / latency_count) if latency_count else 0,
                "response": int(b.get("response_sum", 0) / latency_count) if latency_count else 0}

    def qoder_range(b):
        ctx_count = b.get("ctx_count", 0)
        ctx = (b.get("ctx_sum", 0.0) / ctx_count * 100) if ctx_count else 0.0
        return {"in": b.get("in", 0), "out": b.get("out", 0),
                "sessions": b.get("sessions", 0), "calls": b.get("calls", 0),
                "duration": b.get("duration", 0), "ctx": ctx}

    cranges = {k: claude_range(cc["ranges"][k]) for k in RANGE_KEYS}
    xranges = {k: codex_range(cx["ranges"][k]) for k in RANGE_KEYS}
    granges = {k: gemini_range(gm["ranges"][k]) for k in RANGE_KEYS}
    kranges = {k: grok_range(gk["ranges"][k]) for k in RANGE_KEYS}
    qranges = {k: qoder_range(qd["ranges"][k]) for k in RANGE_KEYS}

    def hermes_range(b):
        denom = b["cr"] + b["cw"] + b["in"]
        hit = (b["cr"] / denom * 100) if denom else 0.0
        models = [{"name": nice_model(n), "in": v["in"], "out": v["out"], "cost": v["cost"]}
                  for n, v in sorted(b["models"].items(), key=lambda kv: -kv[1]["cost"])]
        return {"hit": hit, "in": b["in"], "out": b["out"], "cr": b["cr"], "cw": b["cw"],
                "reason": b["reason"], "cost": b["cost"], "sessions": b["sessions"], "models": models}

    def openclaw_range(b):
        denom = b["cr"] + b["cw"] + b["in"]
        hit = (b["cr"] / denom * 100) if denom else 0.0
        models = [{"name": nice_model(n), "in": v["in"], "out": v["out"], "cost": v["cost"]}
                  for n, v in sorted(b["models"].items(), key=lambda kv: -kv[1]["cost"])]
        return {"tasks": b["tasks"], "completed": b["completed"], "failed": b["failed"],
                "hit": hit, "in": b["in"], "out": b["out"], "cr": b["cr"], "cw": b["cw"],
                "cost": b["cost"], "sessions": len(b["sessions"]), "models": models}

    hranges = {k: hermes_range(hm["ranges"][k]) for k in RANGE_KEYS}
    oranges = {k: openclaw_range(oc["ranges"][k]) for k in RANGE_KEYS}

    def opencode_range(b):
        denom = b["cr"] + b["cw"] + b["in"]
        hit = (b["cr"] / denom * 100) if denom else 0.0
        models = [{"name": nice_model(n), "in": v["in"], "out": v["out"], "cost": v["cost"]}
                  for n, v in sorted(b["models"].items(), key=lambda kv: -kv[1]["cost"])]
        return {"hit": hit, "in": b["in"], "out": b["out"], "cr": b["cr"], "cw": b["cw"],
                "reason": b["reason"], "cost": b["cost"], "sessions": len(b["sessions"]), "models": models}

    ocranges = {k: opencode_range(ocode["ranges"][k]) for k in RANGE_KEYS}

    cur = cc["cur"]
    cur_total = cur["in"] + cur["out"] + cur["cr"] + cur["cw"]

    lim = cx["limits"] or {}
    p5 = (lim.get("primary") or {}).get("used_percent")
    pw = (lim.get("secondary") or {}).get("used_percent")
    r5 = (lim.get("primary") or {}).get("resets_at")
    rw = (lim.get("secondary") or {}).get("resets_at")

    plan = _safe_scan("claude_plan", scan_claude_plan, lambda: {}, errors) or {}

    result = {
        "claude": {
            "ranges": cranges,
            "session_name": cur["name"], "session_total": cur_total,
            "q5": plan.get("q5"), "q5_reset": plan.get("q5_reset"),
            "q7": plan.get("q7"), "q7_reset": plan.get("q7_reset"),
        },
        "codex": {
            "ranges": xranges,
            "p5": p5, "pw": pw, "r5": r5, "rw": rw,
            "plan": cx["plan"],
        },
        "gemini": {
            "ranges": granges,
        },
        "grok": {
            "ranges": kranges,
            "model": gk["model"],
        },
        "qoder": {
            "ranges": qranges,
            "quota": qd.get("quota"),
            "model": qd.get("model"),
        },
        "hermes": {
            "ranges": hranges,
        },
        "openclaw": {
            "ranges": oranges,
        },
        "opencode": {
            "ranges": ocranges,
        },
    }
    if errors:
        result["_errors"] = errors
    return result


_TOKEI_CONFIG = os.path.join(HOME, ".tokei", "config.json")


def _load_tokei_config():
    try:
        with open(_TOKEI_CONFIG) as f:
            return json.load(f)
    except Exception:
        return None


def main_json():
    d = compute()
    meta = _load_json(PRICING_FILE, {}).get("_meta", {})
    d["_pricing"] = {"updated_at": meta.get("updated_at", ""), "count": meta.get("count", 0)}
    print(json.dumps(d, ensure_ascii=False))
    cfg = _load_tokei_config()
    if cfg:
        sync_dir = os.path.expanduser(cfg.get("sync_dir", ""))
        if not sync_dir:
            sync_dir = os.path.join(HOME, ".tokei", "sync")
        device_id = cfg.get("device_id", "")
        if device_id and os.path.isdir(sync_dir):
            import time
            d["_device"] = device_id
            d["_ts"] = int(time.time())
            try:
                with open(os.path.join(sync_dir, f"{device_id}.json"), "w") as f:
                    json.dump(d, f, ensure_ascii=False)
            except OSError:
                pass


def main():
    d = compute()
    c, x = d["claude"], d["codex"]
    ct = c["ranges"]["today"]
    xt = x["ranges"]["today"]
    cc_hit = ct["hit"]
    cc_cost = ct["cost"]
    cur = {"name": c["session_name"]}
    cur_total = c["session_total"]
    cx_hit = xt["hit"]
    p5, pw, r5, rw = x["p5"], x["pw"], x["r5"], x["rw"]

    # ---- menu bar 标题(紧凑):⚡Claude命中率  ◷Codex周额度 ----
    parts = [f"⚡{cc_hit:.0f}"]
    if p5 is not None:
        parts.append(f"◷{p5:.0f}")
    elif pw is not None:
        parts.append(f"◷{pw:.0f}")
    print(" ".join(parts))
    print("---")

    F = "| font=Menlo size=14"
    HEAD = "| font=Menlo-Bold size=15"
    # Claude 块
    print(f"Claude Code {HEAD}")
    print(f"命中率   {cc_hit:5.1f}% {F}")
    print(f"今日 输入   {human(ct['in']):>6} {F}")
    print(f"今日 输出   {human(ct['out']):>6} {F}")
    print(f"今日 缓存读 {human(ct['cr']):>6} {F}")
    print(f"今日 缓存写 {human(ct['cw']):>6} {F}")
    print(f"今日 ≈成本  ${cc_cost:.2f} {F}")
    print(f"  (按 API 价估,非订阅实付) | font=Menlo size=11")
    print(f"本会话({cur['name']}) {human(cur_total)} {F}")
    print("---")
    # Codex 块
    print(f"Codex {HEAD}")
    print(f"命中率   {cx_hit:5.1f}% {F}")
    print(f"今日 输入   {human(xt['in']):>6} {F}")
    print(f"今日 缓存读 {human(xt['cached']):>6} {F}")
    print(f"今日 输出   {human(xt['out']):>6} {F}")
    if xt.get("reason"):
        print(f"今日 推理   {human(xt['reason']):>6} {F}")
    print(f"今日 ≈成本  ${xt['cost']:.2f} {F}")
    print(f"  (按 API 价估,订阅实付不按此) | font=Menlo size=11")
    if p5 is not None:
        print(f"5h 额度  {p5:5.1f}%  reset {fmt_reset(r5)} {F}")
    if pw is not None:
        print(f"周额度   {pw:5.1f}%  reset {fmt_reset(rw)} {F}")
    if x["plan"]:
        print(f"plan: {x['plan']} {F}")
    print("---")
    # Gemini 块
    g = d["gemini"]
    gt = g["ranges"]["today"]
    print(f"Gemini CLI {HEAD}")
    print(f"命中率   {gt['hit']:5.1f}% {F}")
    print(f"今日 输入   {human(gt['in']):>6} {F}")
    print(f"今日 输出   {human(gt['out']):>6} {F}")
    print(f"今日 缓存   {human(gt['cached']):>6} {F}")
    if gt.get("thoughts"):
        print(f"今日 推理   {human(gt['thoughts']):>6} {F}")
    print(f"今日 ≈成本  ${gt['cost']:.2f} {F}")
    print(f"  (按 API 价估,非订阅实付) | font=Menlo size=11")
    print("---")
    # Grok 块(降级:仅上下文 token,不估成本)
    gk = d["grok"]
    kt = gk["ranges"]["today"]
    print(f"Grok CLI {HEAD}")
    print(f"今日 会话   {kt['sessions']:>6} {F}")
    print(f"上下文 token {human(kt['tokens']):>6} {F}")
    if gk.get("model"):
        print(f"model: {gk['model']} {F}")
    print(f"  (仅上下文 token,非消耗量;成本 —) | font=Menlo size=11")
    print("---")
    print("刷新 | refresh=true")


def update_prices():
    """显式联网:拉 OpenRouter /api/v1/models,刷新 pricing.json(不动 overrides)。"""
    import urllib.request
    try:
        with urllib.request.urlopen("https://openrouter.ai/api/v1/models", timeout=30) as r:
            data = json.load(r)["data"]
    except Exception as e:
        print(f"更新失败:{e}", file=sys.stderr)
        return 1

    def mtok(pr, k):
        try:
            return round(float(pr.get(k) or 0) * 1e6, 6)
        except (TypeError, ValueError):
            return 0.0

    models = {}
    for m in data:
        pr = m.get("pricing") or {}
        if not mtok(pr, "prompt") and not mtok(pr, "completion"):
            continue                              # 跳过无价(免费/路由占位)条目
        models[m["id"]] = {"in": mtok(pr, "prompt"), "out": mtok(pr, "completion"),
                           "cache_read": mtok(pr, "input_cache_read"),
                           "cache_write": mtok(pr, "input_cache_write")}
    payload = {"_meta": {"source": "openrouter/api/v1/models",
                         "updated_at": datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S%z"),
                         "count": len(models)},
               "models": models}
    with open(PRICING_FILE, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=1, sort_keys=True)
    print(f"已更新 {len(models)} 个模型 → {PRICING_FILE}")
    try:
        os.remove(_SCAN_CACHE_FILE)
    except OSError:
        pass
    return 0


def _scan_local_models():
    """扫描本地所有日志,收集出现过的模型名。"""
    models = set()
    for f in glob.glob(os.path.join(CLAUDE_DIR, "*", "*.jsonl")):
        try:
            for line in open(f, encoding="utf-8", errors="ignore"):
                if '"model"' not in line:
                    continue
                try:
                    m = json.loads(line).get("message", {}).get("model", "")
                    if m and m != "<synthetic>":
                        models.add(m)
                except Exception:
                    pass
        except OSError:
            pass
    for f in glob.glob(os.path.join(GEMINI_DIR, "*", "chats", "session-*.json")):
        try:
            for msg in json.load(open(f)).get("messages", []):
                m = msg.get("model", "")
                if m:
                    models.add(m)
        except Exception:
            pass
    return models


def _is_exact_match(model: str):
    """检查模型是否有精确价格(非回退)。"""
    s = (model or "").strip()
    if not s or s.lower() == "<synthetic>":
        return True
    if s in _OV_ALIASES:
        return True
    norm = _normalize(model)
    return norm and (norm in _OV_MODELS or norm in _PRICING_DB or norm in _DEFAULT_PRICES)


def _estimate_from_sibling(model: str):
    """尝试从同家族同 tier 的其他版本估价。"""
    low = model.lower()
    tiers = ["max", "plus", "flash", "lite", "turbo", "pro", "mini"]
    tier = None
    for t in tiers:
        if t in low:
            tier = t
            break
    if not tier:
        return None
    all_models = {}
    all_models.update(_PRICING_DB)
    all_models.update(_OV_MODELS)
    candidates = []
    for cid, p in all_models.items():
        if tier in cid.lower():
            family_match = False
            for kw, _ in _FAMILY:
                if kw in low and kw in cid.lower():
                    family_match = True
                    break
            if family_match:
                candidates.append((cid, p))
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0], reverse=True)
    best_cid, best_p = candidates[0]
    return {"source": best_cid, "in": best_p.get("in", 0), "out": best_p.get("out", 0),
            "cache_read": best_p.get("cache_read", 0), "cache_write": best_p.get("cache_write", 0)}


def update_unknown():
    """扫描本地日志找未知模型,尝试从 OpenRouter 或同族估价,写入 overrides。"""
    models = _scan_local_models()
    unknown = []
    for m in sorted(models):
        if _is_exact_match(m):
            continue
        rid = _resolve_id(m)
        cur = _raw_price(rid)
        est = _estimate_from_sibling(m)
        unknown.append({"model": m, "resolved_to": rid,
                        "current": {"in": cur["in"], "out": cur["out"]},
                        "estimate": est})

    if not unknown:
        result = {"status": "ok", "message": "所有模型价格已匹配", "count": 0, "added": []}
        print(json.dumps(result, ensure_ascii=False))
        return 0

    try:
        ovr = json.load(open(OVERRIDES_FILE, encoding="utf-8"))
    except Exception:
        ovr = {"models": {}, "aliases": {}}

    added = []
    for u in unknown:
        name = u["model"]
        norm = _normalize(name)
        if not norm:
            continue
        if u["estimate"]:
            e = u["estimate"]
            ovr["models"][norm] = {"in": e["in"], "out": e["out"],
                                   "cache_read": e["cache_read"], "cache_write": e["cache_write"]}
            if name != norm:
                ovr["aliases"][name] = norm
            added.append({"model": name, "canonical": norm, "price": e,
                          "method": f"estimated from {e['source']}"})
        else:
            if name != norm and norm not in ovr.get("aliases", {}):
                ovr["aliases"][name] = norm
            added.append({"model": name, "canonical": norm, "price": None,
                          "method": "no estimate available, using fallback"})

    with open(OVERRIDES_FILE, "w", encoding="utf-8") as f:
        json.dump(ovr, f, ensure_ascii=False, indent=2)
    try:
        os.remove(_SCAN_CACHE_FILE)
    except OSError:
        pass

    result = {"status": "ok", "count": len(added), "added": added}
    print(json.dumps(result, ensure_ascii=False))
    return 0


def daily_costs():
    """输出按天+按模型的成本 JSON(从扫描缓存读,无额外 I/O)。"""
    cache = _load_scan_cache()
    days = {}
    models = {}

    _empty = lambda: {"claude": 0.0, "codex": 0.0,
                       "c_in": 0, "c_out": 0, "c_cr": 0, "c_cw": 0,
                       "x_in": 0, "x_out": 0, "x_cached": 0, "x_reason": 0,
                       "tokens": 0, "sessions": 0}

    for fp, entry in cache.get("claude", {}).items():
        for dk, day in entry.get("days", {}).items():
            d = days.setdefault(dk, _empty())
            d["claude"] += day.get("cost", 0)
            d["c_in"] += day.get("in", 0); d["c_out"] += day.get("out", 0)
            d["c_cr"] += day.get("cr", 0); d["c_cw"] += day.get("cw", 0)
            d["tokens"] += day.get("in", 0) + day.get("out", 0) + day.get("cr", 0) + day.get("cw", 0)
            d["sessions"] += 1
            for mn, mv in day.get("models", {}).items():
                nm = nice_model(mn)
                m = models.setdefault(nm, {"cost": 0.0, "in": 0, "out": 0, "cr": 0, "cw": 0, "tool": "claude"})
                m["cost"] += mv.get("cost", 0)
                m["in"] += mv.get("in", 0); m["out"] += mv.get("out", 0)
                m["cr"] += mv.get("cr", 0); m["cw"] += mv.get("cw", 0)

    for fp, entry in cache.get("codex", {}).items():
        for dk, day in entry.get("days", {}).items():
            d = days.setdefault(dk, _empty())
            d["codex"] += day.get("cost", 0)
            d["x_in"] += day.get("in", 0); d["x_out"] += day.get("out", 0)
            d["x_cached"] += day.get("cached", 0); d["x_reason"] += day.get("reason", 0)
            # Codex 的 in 已含 cached,总量 = in + out + reason(不重复加 cached)
            d["tokens"] += day.get("in", 0) + day.get("out", 0) + day.get("reason", 0)

    for fp, entry in cache.get("hermes", {}).items():
        for dk, day in entry.get("days", {}).items():
            d = days.setdefault(dk, _empty())
            d["tokens"] += day.get("in", 0) + day.get("out", 0) + day.get("cr", 0) + day.get("cw", 0) + day.get("reason", 0)

    for fp, entry in cache.get("qoder", {}).items():
        for dk, day in entry.get("days", {}).items():
            d = days.setdefault(dk, _empty())
            d["tokens"] += day.get("in", 0) + day.get("out", 0)

    codex_total = sum(d["codex"] for d in days.values())
    codex_in = sum(d["x_in"] for d in days.values())
    codex_out = sum(d["x_out"] for d in days.values())
    codex_reason = sum(d["x_reason"] for d in days.values())
    if codex_total > 0:
        models["GPT-5.5 (Codex)"] = {"cost": round(codex_total, 2), "in": codex_in, "out": codex_out,
                                      "reason": codex_reason, "tool": "codex"}

    daily = [{"date": dk, "claude": round(v["claude"], 2), "codex": round(v["codex"], 2),
              "total": round(v["claude"] + v["codex"], 2),
              "c_in": v["c_in"], "c_out": v["c_out"], "c_cr": v["c_cr"], "c_cw": v["c_cw"],
              "x_in": v["x_in"], "x_out": v["x_out"], "x_cached": v["x_cached"], "x_reason": v["x_reason"],
              "tokens": v["tokens"]}
             for dk, v in sorted(days.items())]
    model_list = []
    for n, v in sorted(models.items(), key=lambda kv: -kv[1]["cost"]):
        if v["cost"] <= 0:
            continue
        if v.get("tool") == "codex":
            total_tok = v["in"] + v["out"] + v.get("reason", 0)   # in 已含 cached
        else:
            total_tok = v["in"] + v["out"] + v.get("cr", 0) + v.get("cw", 0)
        out_k = v["out"] / 1000 if v["out"] else 0
        cost_per_k = round(v["cost"] / out_k, 3) if out_k > 0 else 0
        out_ratio = round(v["out"] / total_tok * 100, 1) if total_tok > 0 else 0
        model_list.append({"name": n, "cost": round(v["cost"], 2),
                           "in": v["in"], "out": v["out"], "cr": v.get("cr", 0), "cw": v.get("cw", 0),
                           "tokens": total_tok, "tool": v["tool"],
                           "cost_per_k": cost_per_k, "out_ratio": out_ratio})

    print(json.dumps({"daily": daily, "models": model_list}, ensure_ascii=False))


def _streak_info(dates):
    """dates: ISO 日期字符串列表。返回 (最长连续天数, 当前连续天数)。"""
    if not dates:
        return 0, 0
    ds = sorted(date.fromisoformat(x) for x in dates)
    max_run = run = 1
    for i in range(1, len(ds)):
        run = run + 1 if (ds[i] - ds[i - 1]).days == 1 else 1
        if run > max_run:
            max_run = run
    cur = 0
    if (date.today() - ds[-1]).days <= 1:   # 仅当最近活跃日是今/昨天才算"当前连续"
        cur = 1
        for i in range(len(ds) - 1, 0, -1):
            if (ds[i] - ds[i - 1]).days == 1:
                cur += 1
            else:
                break
    return max_run, cur


def wrapped():
    """Tokei 回顾:作息 / 项目 / 连续 / 成就。纯读扫描缓存(Claude),不联网。"""
    cache = _load_scan_cache()
    if not cache.get("claude"):
        compute()                       # 缓存空则先扫一遍(同 --json 路径)
        cache = _load_scan_cache()
    fc = cache.get("claude", {})

    hours = [0] * 24
    weekday = [0] * 7
    day_tokens = {}
    proj_tok = {}
    day_projs = {}
    model_tok = {}
    total_tokens = 0
    total_cost = 0.0

    for f, entry in fc.items():
        if not isinstance(entry, dict):
            continue
        h = entry.get("hours")
        if h and len(h) == 24:
            for i in range(24):
                hours[i] += h[i]
        proj_path = entry.get("proj") or ""
        proj = os.path.basename(proj_path.rstrip("/")) or "?"
        for dk, day in entry.get("days", {}).items():
            tok = day["in"] + day["out"] + day["cr"] + day["cw"]
            day_tokens[dk] = day_tokens.get(dk, 0) + tok
            total_tokens += tok
            total_cost += day.get("cost", 0)
            pt = proj_tok.setdefault(proj, [0, 0.0])
            pt[0] += tok; pt[1] += day.get("cost", 0)
            day_projs.setdefault(dk, set()).add(proj)
            weekday[date.fromisoformat(dk).weekday()] += tok
            for mn, mv in day.get("models", {}).items():
                nm = nice_model(mn)
                model_tok[nm] = model_tok.get(nm, 0) + mv["in"] + mv["out"] + mv["cr"] + mv["cw"]

    active = sorted(day_tokens.keys())
    streak_max, streak_cur = _streak_info(active)
    busiest_dk, busiest_tok = (max(day_tokens.items(), key=lambda kv: kv[1])
                               if day_tokens else ("", 0))
    top_model_name, top_model_tok = (max(model_tok.items(), key=lambda kv: kv[1])
                                     if model_tok else ("-", 0))
    projects = sorted(
        ({"name": p, "tokens": v[0], "cost": round(v[1], 2)} for p, v in proj_tok.items()),
        key=lambda x: -x["tokens"])[:8]
    max_projs_day = max((len(s) for s in day_projs.values()), default=0)
    night = sum(hours[0:6])
    night_share = round(night / total_tokens * 100, 1) if total_tokens else 0.0

    ach = []
    def add(icon, title, desc, tint):
        ach.append({"icon": icon, "title": title, "desc": desc, "tint": tint})

    # Token 里程碑(金,取最高档)
    if total_tokens >= 1_000_000_000_000:
        add("crown.fill", "万亿俱乐部", f"{total_tokens/1e12:.2f} 万亿 token", "gold")
    elif total_tokens >= 100_000_000_000:
        add("hexagon.fill", "千亿俱乐部", f"{total_tokens/1e8:.0f} 亿 token", "gold")
    elif total_tokens >= 10_000_000_000:
        add("diamond.fill", "百亿俱乐部", f"{total_tokens/1e8:.0f} 亿 token", "gold")
    elif total_tokens >= 1_000_000_000:
        add("diamond", "十亿俱乐部", f"{total_tokens/1e8:.1f} 亿 token", "gold")

    # 成本里程碑(绿,取最高档)
    if total_cost >= 100000:
        add("dollarsign.circle.fill", "十万刀", f"≈${int(total_cost):,}", "green")
    elif total_cost >= 10000:
        add("banknote.fill", "破万刀", f"≈${int(total_cost):,}", "green")
    elif total_cost >= 1000:
        add("banknote", "破千刀", f"≈${int(total_cost):,}", "green")

    # 连续打卡(火橙,取最高档)
    if streak_max >= 100:
        add("flame.fill", "百日筑基", f"连续 {streak_max} 天", "coral")
    elif streak_max >= 30:
        add("flame.fill", "铁人", f"连续 {streak_max} 天", "coral")
    elif streak_max >= 7:
        add("flame.fill", "坚持", f"连续 {streak_max} 天", "coral")

    # 单日爆发(火橙)
    if busiest_tok >= 1_000_000_000:
        add("bolt.fill", "爆肝日", f"单日 {busiest_tok/1e8:.0f} 亿 token", "coral")

    # 项目维度(青蓝)
    if max_projs_day >= 5:
        add("square.grid.3x3.fill", "多线作战", f"单日 {max_projs_day} 个项目", "blue")
    elif max_projs_day >= 3:
        add("square.grid.2x2.fill", "多面手", f"单日 {max_projs_day} 个项目", "blue")
    top_share = (max(v[0] for v in proj_tok.values()) / total_tokens * 100) if (proj_tok and total_tokens) else 0
    if top_share >= 50:
        add("scope", "专一", f"主项目占 {top_share:.0f}%", "blue")
    if len(proj_tok) >= 10:
        add("rectangle.3.group.fill", "广撒网", f"{len(proj_tok)} 个项目", "blue")

    # 作息彩蛋(紫)
    if night_share >= 5:
        add("moon.stars.fill", "夜猫子", f"{night_share:.0f}% 在凌晨", "purple")
    morning_share = (sum(hours[5:9]) / total_tokens * 100) if total_tokens else 0
    if morning_share >= 12:
        add("sunrise.fill", "早起鸟", f"{morning_share:.0f}% 在清晨", "purple")
    weekend_share = ((weekday[5] + weekday[6]) / total_tokens * 100) if total_tokens else 0
    if weekend_share >= 30:
        add("beach.umbrella.fill", "周末战士", f"周末占 {weekend_share:.0f}%", "purple")

    # 资历(玫红)
    if len(active) >= 100:
        add("calendar", "元老", f"{len(active)} 天活跃", "pink")

    print(json.dumps({
        "total_tokens": total_tokens,
        "total_cost": round(total_cost, 2),
        "active_days": len(active),
        "streak_max": streak_max,
        "streak_cur": streak_cur,
        "busiest": {"date": busiest_dk, "tokens": busiest_tok},
        "top_model": {"name": top_model_name, "tokens": top_model_tok},
        "hours": hours,
        "weekday": weekday,
        "projects": projects,
        "max_projs_day": max_projs_day,
        "night_share": night_share,
        "first_day": active[0] if active else "",
        "achievements": ach,
    }, ensure_ascii=False))


def projects():
    """项目足迹:从缓存聚合所有项目路径、活跃时间、session 数、token、成本。"""
    cache = _load_scan_cache()
    if not cache.get("claude"):
        compute()
        cache = _load_scan_cache()

    proj_map = {}  # path → {sessions, tokens, cost, last_active, model_tok}

    # Claude sessions
    for f, entry in cache.get("claude", {}).items():
        if not isinstance(entry, dict):
            continue
        proj_path = entry.get("proj") or ""
        if not proj_path or proj_path == "?":
            continue
        p = proj_map.setdefault(proj_path, {"sessions": 0, "tokens": 0, "cost": 0.0,
                                             "last_active": "", "model_tok": {}, "tools": set()})
        p["sessions"] += 1
        p["tools"].add("claude")
        for dk, day in entry.get("days", {}).items():
            tok = day["in"] + day["out"] + day["cr"] + day["cw"]
            p["tokens"] += tok
            p["cost"] += day.get("cost", 0)
            if dk > p["last_active"]:
                p["last_active"] = dk
            for mn, mv in day.get("models", {}).items():
                nm = nice_model(mn)
                p["model_tok"][nm] = p["model_tok"].get(nm, 0) + mv["in"] + mv["out"] + mv["cr"] + mv["cw"]

    # Grok sessions (cwd encoded in directory name)
    from urllib.parse import unquote
    for sm in glob.glob(os.path.join(GROK_DIR, "*", "*", "summary.json")):
        parts = sm.split(os.sep)
        try:
            cwd_encoded = parts[-3]
            grok_path = unquote(cwd_encoded)
            if not grok_path.startswith("/"):
                continue
            with open(sm, "r", encoding="utf-8", errors="ignore") as fh:
                s = json.load(fh)
            dt = parse_ts(s.get("updated_at") or s.get("created_at") or "")
            if dt is None:
                continue
            dk = dt.astimezone().date().isoformat()
            p = proj_map.setdefault(grok_path, {"sessions": 0, "tokens": 0, "cost": 0.0,
                                                 "last_active": "", "model_tok": {}, "tools": set()})
            p["sessions"] += 1
            p["tools"].add("grok")
            if dk > p["last_active"]:
                p["last_active"] = dk
        except Exception:
            continue

    # 检测本地 LISTEN 端口,匹配项目 cwd
    port_map = _detect_local_servers(set(proj_map.keys()))

    result = []
    for path, info in proj_map.items():
        name = os.path.basename(path.rstrip("/")) or path
        top_model = max(info["model_tok"].items(), key=lambda kv: kv[1])[0] if info["model_tok"] else ""
        entry = {
            "path": path,
            "name": name,
            "last_active": info["last_active"],
            "sessions": info["sessions"],
            "tokens": info["tokens"],
            "cost": round(info["cost"], 2),
            "top_model": top_model,
            "tools": sorted(info["tools"]),
        }
        if path in port_map:
            entry["ports"] = sorted(port_map[path])
        result.append(entry)
    result.sort(key=lambda x: x["last_active"], reverse=True)
    print(json.dumps(result, ensure_ascii=False))


def _detect_local_servers(project_paths):
    """检测哪些项目目录下有进程正在监听 TCP 端口。返回 {path: [port, ...]}。"""
    import subprocess
    try:
        # 1) pid → ports (LISTEN)
        out1 = subprocess.check_output(
            ["lsof", "-iTCP", "-sTCP:LISTEN", "-P", "-n", "-F", "pn"],
            stderr=subprocess.DEVNULL, timeout=10, text=True)
        pid_ports = {}
        cur_pid = None
        for line in out1.strip().split("\n"):
            if line.startswith("p"):
                cur_pid = line[1:]
            elif line.startswith("n") and cur_pid:
                addr = line[1:]
                port = addr.rsplit(":", 1)[-1] if ":" in addr else None
                if port and port.isdigit():
                    p = int(port)
                    if 1024 <= p <= 65535:
                        pid_ports.setdefault(cur_pid, set()).add(p)

        if not pid_ports:
            return {}

        # 2) pid → cwd (只查有监听端口的 pid，避免全系统扫描超时)
        pid_arg = ",".join(pid_ports.keys())
        out2 = subprocess.check_output(
            ["lsof", "-a", "-d", "cwd", "-p", pid_arg, "-F", "pn"],
            stderr=subprocess.DEVNULL, timeout=10, text=True)
        pid_cwd = {}
        cur_pid = None
        for line in out2.strip().split("\n"):
            if line.startswith("p"):
                cur_pid = line[1:]
            elif line.startswith("n") and cur_pid:
                pid_cwd[cur_pid] = line[1:]

        # 3) 交叉匹配: 进程 cwd 是项目路径或其子目录
        #    匹配最深(最长)的项目路径，避免 home 目录吃掉所有端口
        home = os.path.expanduser("~")
        sorted_projs = sorted(project_paths, key=len, reverse=True)
        result = {}
        for pid, ports in pid_ports.items():
            cwd = pid_cwd.get(pid, "")
            if not cwd or cwd == home:
                continue
            for proj in sorted_projs:
                if proj == home:
                    continue
                if cwd == proj or cwd.startswith(proj + "/"):
                    result.setdefault(proj, set()).update(ports)
                    break
        return result
    except Exception:
        return {}


if __name__ == "__main__":
    if "--update-prices" in sys.argv:
        sys.exit(update_prices())
    if "--update-unknown" in sys.argv:
        sys.exit(update_unknown())
    if "--daily-costs" in sys.argv:
        daily_costs()
    elif "--projects" in sys.argv:
        projects()
    elif "--wrapped" in sys.argv:
        wrapped()
    elif "--json" in sys.argv:
        main_json()
    else:
        main()
