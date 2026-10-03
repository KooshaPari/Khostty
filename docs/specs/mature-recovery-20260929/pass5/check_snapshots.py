#!/usr/bin/env python3
"""Check byte-exact source snapshots. Static proof only, not native execution."""
import argparse, hashlib, json, re, sys
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--out",type=Path,required=True)
args=parser.parse_args()
ROOT=Path(__file__).parent
files={"sources/App.zig":"7e677fb91431e6d19f4347f1fd352e3a341d5df9", "sources/apprt.zig":"67dd08c54744b947b0cb236c08ed0c542b3e8076"}
checks=[]
for path,want in files.items():
 raw=(ROOT/path).read_bytes();got=hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()
 checks.append(dict(path=path,expected_blob=want,observed_blob=got,pass_=want==got))
 if want!=got: raise SystemExit(f"source copy mismatch {path}: {got}")
app=(ROOT/"sources/App.zig").read_text();apprt=(ROOT/"sources/apprt.zig").read_text()
for name in ("init","registerWindowClass","run"):
 # This is deliberately exact on the verified file; it is not a general Zig parser.
 pattern=r'pub fn '+name+r'\([^\n]*\) !void \{\s*return error.Unimplemented;\s*\}'
 checks.append(dict(case=f"windows_{name}_unimplemented",pass_=bool(re.search(pattern,app))))
checks.append(dict(case="windows_runtime_selected",pass_=".windows => windows," in apprt))
checks.append(dict(case="ipc_export_is_legacy_mod",pass_='pub const ipc = @import("apprt/ipc/mod.zig");' in apprt))
result=dict(product="KooshaPari/Khostty",source="a29aa9c6553d9f42aa68e2919116c0f6d53f329d",checks=checks,
 checker_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),python=sys.version,
 native_executed=False,subject="BYTE_VERIFIED_STATIC_SOURCE",product_gui_verdict="UNIMPLEMENTED_AT_SNAPSHOT",
 limitation="Local source hash and source assertions only; not a Zig build, caller-graph completeness proof or runtime test.")
args.out.parent.mkdir(parents=True,exist_ok=True)
with args.out.open("x") as f: f.write(json.dumps(result,indent=2)+"\n")
print(json.dumps(result,indent=2));raise SystemExit(0 if all(c["pass_"] for c in checks) else 1)
