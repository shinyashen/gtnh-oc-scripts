#!/usr/bin/env python3
"""从 GTNH 中文维基(灰机wiki)页内搬运 <syntaxhighlight lang="lua"> 代码块。

用法: python3 scripts/wiki_sync.py
行为:
  对 PAGES 中每个页面调 MediaWiki API 取最新 wikitext,提取全部 lua 代码块,
  写入对应组的 wiki/<页名>/block-N.lua,并在同目录写 revision.json 记录
  页面标题 / revid / timestamp / 块数;revid 未变则跳过(幂等)。
  碰到 Cloudflare 人机验证(响应不是 JSON)时打印警告并跳过该页,不影响其他页面。
"""

import json
import re
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

API = "https://gtnh.huijiwiki.com/api.php"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")

# (维基页标题, 目标组)
PAGES = [
    ("指南:血魔法祭坛自动化", "blood-altar"),
    ("指南:基于OC的无线电网监控", "wireless-eu-monitor"),
    ("指南:基于OC的太空电梯智能管理", "space-elevator-miner"),
    ("指南:亚稳态黑洞遏制场自动化", "blackhole-compressor"),
]

REPO_ROOT = Path(__file__).resolve().parent.parent
BLOCK_RE = re.compile(r'<syntaxhighlight[^>]*\blang="lua"[^>]*>(.*?)</syntaxhighlight>',
                      re.S | re.I)


def fetch(title):
    """用 curl 子进程取 MediaWiki API(Python urllib 的 TLS 指纹会被 Cloudflare 拦 403)。"""
    q = urllib.parse.urlencode({
        "action": "query",
        "prop": "revisions",
        "titles": title,
        "rvprop": "ids|timestamp|content",
        "rvslots": "main",
        "format": "json",
        "formatversion": "2",
    })
    url = "%s?%s" % (API, q)
    p = subprocess.run(["curl", "-fsSL", "--max-time", "30", "-A", UA, url],
                       capture_output=True)
    if p.returncode != 0:
        raise RuntimeError("curl exit %d" % p.returncode)
    raw = p.stdout.decode("utf-8", "replace")
    if "请稍候" in raw[:200] or raw.lstrip()[:1] != "{":
        raise RuntimeError("Cloudflare challenge or non-JSON response")
    d = json.loads(raw)
    page = d["query"]["pages"][0]
    if "missing" in page:
        raise RuntimeError("page missing: %s" % title)
    rev = page["revisions"][0]
    content = rev["slots"]["main"]["content"]
    return rev, content


def slugify(title):
    return title.replace(":", "-").replace("/", "-")


def main():
    changed = 0
    for title, group in PAGES:
        outdir = REPO_ROOT / "src" / group / "wiki" / slugify(title)
        rev = content = None
        last_err = None
        for attempt in range(3):
            try:
                rev, content = fetch(title)
                break
            except Exception as e:
                last_err = e
                time.sleep(4)
        if rev is None:
            print("[WARN] %s: %s (跳过)" % (title, last_err), flush=True)
            continue
        old = {}
        revfile = outdir / "revision.json"
        if revfile.is_file():
            try:
                old = json.loads(revfile.read_text(encoding="utf-8"))
            except Exception:
                old = {}
        if old.get("revid") == rev["revid"]:
            print("[skip] %s @ revid %s (unchanged)" % (title, rev["revid"]), flush=True)
            continue
        outdir.mkdir(parents=True, exist_ok=True)
        blocks = [b.rstrip() + "\n" for b in BLOCK_RE.findall(content) if b.strip()]
        if not blocks:
            print("[WARN] %s: 页面当前没有 lua 代码块,仅更新 revision.json" % title, flush=True)
        for i, b in enumerate(blocks, 1):
            (outdir / ("block-%d.lua" % i)).write_text(b, encoding="utf-8", newline="\n")
        # 清掉旧的多余块(页面删块后同步删除)
        for p in outdir.glob("block-*.lua"):
            n = int(p.stem.split("-")[1])
            if n > len(blocks):
                p.unlink()
        revfile.write_text(json.dumps({
            "title": title,
            "revid": rev["revid"],
            "timestamp": rev["timestamp"],
            "blocks": len(blocks),
            "source": "https://gtnh.huijiwiki.com/wiki/" + urllib.parse.quote(title.replace(" ", "_")),
        }, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print("[sync] %s -> revid %s, %d blocks" % (title, rev["revid"], len(blocks)), flush=True)
        changed += 1
    print("done, %d page(s) updated" % changed, flush=True)


if __name__ == "__main__":
    sys.exit(main())
