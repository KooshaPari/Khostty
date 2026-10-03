#!/usr/bin/env python3
"""Real-checkout K-E01 caller/mount audit.

Exit 0 means the EXPECTED frozen-source architecture was observed. It does not
mean Khostty works. Exact source SHA is supplied by the workflow.
"""
from __future__ import annotations
import argparse, hashlib, json, subprocess
from pathlib import Path

SYMBOLS = {
    "AppHost": "src/apprt/ipc/app_host.zig",
    "Server.bind": "src/apprt/ipc/server.zig",
    "pane.Manager.init": "src/apprt/ipc/",
    "setEventBroker": "src/apprt/ipc/",
    "events.Broker.init": "src/apprt/ipc/",
}

def git(repo: Path, *args: str, allow1: bool=False):
    p=subprocess.run(["git","-C",str(repo),*args],capture_output=True,text=True,check=False)
    if p.returncode not in ((0,1) if allow1 else (0,)):
        raise RuntimeError(p.stderr)
    return p

def main():
    ap=argparse.ArgumentParser();ap.add_argument("--repo",type=Path,required=True);ap.add_argument("--source",required=True);ap.add_argument("--out",type=Path,required=True)
    a=ap.parse_args(); repo=a.repo.resolve()
    if git(repo,"rev-parse",f"{a.source}^{{commit}}").stdout.strip()!=a.source:
        raise ValueError("source must be exact commit")
    rows={}
    violations=[]
    for symbol,allowed in SYMBOLS.items():
        p=git(repo,"grep","-n","-F",symbol,a.source,"--","src",allow1=True)
        matches=[line for line in p.stdout.splitlines() if line]
        rows[symbol]=matches
        for line in matches:
            # git grep at a tree prints <sha>:<path>:<line>:...
            rest=line.split(":",1)[1] if ":" in line else line
            path=rest.split(":",1)[0]
            if allowed.endswith("/"):
                ok=path.startswith(allowed)
            else:
                ok=path==allowed
            if not ok:
                violations.append({"symbol":symbol,"match":line})
    protocol=git(repo,"show",f"{a.source}:src/apprt/ipc/protocol.md").stdout
    explicit={
      "protocol_says_server_not_started":"server is therefore not yet started from the app" in protocol,
      "protocol_says_app_thread_hop_unwired":"The app-thread hop is not wired yet" in protocol,
    }
    result={
      "schema_version":1,"product":"KooshaPari/Khostty","source":a.source,
      "subject":"REAL_CHECKOUT_CALLER_GRAPH_NOT_PRODUCT_ACCEPTANCE",
      "symbol_matches":rows,"unexpected_non_ipc_src_matches":violations,
      "explicit_protocol_controls":explicit,
      "expected_unmounted_baseline_observed":not violations and all(explicit.values()),
    }
    raw=json.dumps(result,indent=2)+"\n";a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(raw)
    print(raw,end="");return 0 if result["expected_unmounted_baseline_observed"] else 1
if __name__=="__main__": raise SystemExit(main())
