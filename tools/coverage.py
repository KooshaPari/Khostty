#!/usr/bin/env python3
"""Measure emitted executable source lines, never total-source coverage."""
import pathlib
import json
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def classify_filename(root, raw, source):
    """Cobertura filenames are relative to XML sources, never the process cwd."""
    path = pathlib.Path(raw)
    if path.is_absolute():
        candidates = {path.resolve()}
    else:
        roots = [pathlib.Path(node.text) for node in root.findall("./sources/source")
                 if node.text]
        if not roots or any(not base.is_absolute() for base in roots):
            raise RuntimeError(f"Missing or nonabsolute Cobertura source roots: {raw}")
        candidates = {(base / path).resolve() for base in roots}
    existing = {candidate for candidate in candidates if candidate.is_file()}
    if len(existing) != 1:
        raise RuntimeError(f"Unresolvable or ambiguous coverage filename: {raw}: {candidates}")
    filename = existing.pop()
    if filename.is_relative_to(source):
        return filename, "first-party"
    # Only checked-in dependency trees are known exclusions. Cache/toolchain and
    # arbitrary external paths remain unknown and must stop publication.
    for name in ("pkg", "vendor"):
        dependency = source.parent / name
        if dependency.is_dir() and filename.is_relative_to(dependency.resolve()):
            return filename, "dependency"
    raise RuntimeError(f"Coverage escaped source scope: {filename}")


def main():
    source = pathlib.Path(sys.argv[1]).resolve()
    output = pathlib.Path(sys.argv[2]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    # Every invocation has fresh data. Old reports must never imply success.
    run = pathlib.Path(tempfile.mkdtemp(prefix="run-", dir=output))
    lines = {}
    audit = []
    audit_path = run / "scope-audit.json"
    for index, binary in enumerate(sys.argv[3:]):
        destination = run / str(index)
        subprocess.run(
            ["kcov", f"--include-path={source}", str(destination), binary],
            check=True,
        )
        reports = sorted({path.resolve() for path in destination.glob("*/cobertura.xml")})
        if len(reports) != 1:
            raise RuntimeError(f"Expected one coverage report for {binary}: {reports}")
        root = ET.parse(reports[0]).getroot()
        for cls in root.findall(".//class"):
            raw = cls.attrib["filename"]
            try:
                filename, scope = classify_filename(root, raw, source)
            except RuntimeError as error:
                audit.append({"binary": binary, "reported_filename": raw,
                              "classification": "unknown", "error": str(error)})
                audit_path.write_text(json.dumps(audit, indent=2) + "\n")
                raise
            if scope == "dependency":
                audit.append({"binary": binary, "reported_filename": raw,
                              "filename": str(filename), "classification": scope,
                              "executable_lines": len(cls.findall("./lines/line")),
                              "hit_lines": sum(int(line.attrib["hits"]) > 0
                                               for line in cls.findall("./lines/line"))})
                audit_path.write_text(json.dumps(audit, indent=2) + "\n")
                continue
            for line in cls.findall("./lines/line"):
                key = (str(filename), int(line.attrib["number"]))
                lines[key] = lines.get(key, False) or int(line.attrib["hits"]) > 0
    if not lines:
        raise RuntimeError("No executable source lines were measured")
    covered = sum(lines.values())
    audit_path.write_text(json.dumps(audit, indent=2) + "\n")
    message = (
        f"Emitted executable source line coverage: {covered}/{len(lines)} "
        f"({100 * covered / len(lines):.2f}%)\n"
        "Not total-source coverage: Zig omits unanalyzed declarations.\n"
        "Scope: configured Zig test binaries only, not Xcode/UI or other targets.\n"
        f"First-party root: {source}\n"
        f"Dependency file observations excluded: {len(audit)} (pkg/ and vendor/ only).\n"
        f"Scope audit (including dependency hit lines): {audit_path}\n"
        f"Raw reports: {run}\n"
    )
    (run / "summary.txt").write_text(message)
    print(message, end="")


if __name__ == "__main__":
    main()
