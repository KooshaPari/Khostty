#!/usr/bin/env python3
"""Diagnose K-F14/K-F15 against an exact frozen Khostty Git commit.

Exit 0 means the expected evidence defects were reproduced. It is NOT a CI/product green.
"""
from __future__ import annotations
import argparse,hashlib,json,re,subprocess
from pathlib import Path

CI=".github/workflows/ci.yml"
BUILD="khostty-vt/build.rs"
TEST="khostty-vt/tests/terminal.rs"

def git(repo:Path,*args:str)->bytes:
    r=subprocess.run(["git","-C",str(repo),*args],capture_output=True,check=False,timeout=20)
    if r.returncode:raise RuntimeError(r.stderr.decode(errors="replace"))
    return r.stdout

def show(repo:Path,sha:str,path:str)->str:
    return git(repo,"show",f"{sha}:{path}").decode("utf-8")

def blob(repo:Path,sha:str,path:str)->str:
    return git(repo,"rev-parse",f"{sha}:{path}").decode().strip()

def main()->int:
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("--repo",type=Path,required=True);p.add_argument("--source",required=True);p.add_argument("--out",type=Path,required=True);a=p.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}",a.source):raise ValueError("exact source SHA required")
    ci,build,test=(show(a.repo,a.source,x) for x in (CI,BUILD,TEST))
    # Deliberately exact enough to fail if the workflow changes rather than silently overgeneralize.
    advisory_jobs=len(re.findall(r"(?m)^\s+continue-on-error:\s*true\s*$",ci))
    swallowed=len(re.findall(r'\|\|\s*echo\s+"::warning::',ci))
    mac_disabled=bool(re.search(r"(?m)^\s+if:\s*\$\{\{\s*false\s*\}\}\s*$",ci))
    test_job=re.search(r"(?ms)^  test:\n(.*?)(?=^  \S|\Z)",ci)
    test_body=test_job.group(1) if test_job else ""
    test_echo="All test stages passed" in test_body
    test_commands=bool(re.search(r"(?m)^\s*(cargo test|go test|pytest|python -m pytest|npm test|zig build test)\b",test_body))
    cfg_elision="#![cfg(ghostty_vt_linked)]" in test
    permissive_link=("no prebuilt libghostty-vt found" in build and "typecheck but not link" in build)
    observations={
      "continue_on_error_true_count":advisory_jobs,
      "warning_swallowed_command_count":swallowed,
      "macos_build_disabled":mac_disabled,
      "ci_test_echoes_success":test_echo,
      "ci_test_contains_actual_test_command":test_commands,
      "rust_native_tests_cfg_elided_without_library":cfg_elision,
      "rust_build_allows_typecheck_without_link":permissive_link,
    }
    reproduced=(advisory_jobs>0 and swallowed>0 and mac_disabled and test_echo and not test_commands and cfg_elision and permissive_link)
    result={
      "subject":"K-F14_K-F15_FROZEN_CI_EVIDENCE_DIAGNOSIS_NOT_PRODUCT_ACCEPTANCE",
      "source":a.source,
      "source_blobs":{CI:blob(a.repo,a.source,CI),BUILD:blob(a.repo,a.source,BUILD),TEST:blob(a.repo,a.source,TEST)},
      "observations":observations,
      "expected_false_green_mechanisms_reproduced":reproduced,
      "policy_consequence":"A successful generic CI/cargo-test status is insufficient. Acceptance must require an exact expected-job matrix, non-advisory failures, and a positive linked-native integration-test sentinel."
    }
    a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps(result,indent=2));return 0 if reproduced else 1
if __name__=="__main__":raise SystemExit(main())
