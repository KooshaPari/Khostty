#!/usr/bin/env python3
"""Measure emitted executable source lines, never total-source coverage."""
import pathlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def main():
    source = pathlib.Path(sys.argv[1]).resolve()
    output = pathlib.Path(sys.argv[2]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    # Every invocation has fresh data. Old reports must never imply success.
    run = pathlib.Path(tempfile.mkdtemp(prefix="run-", dir=output))
    lines = {}
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
            filename = pathlib.Path(cls.attrib["filename"]).resolve()
            if not filename.is_relative_to(source):
                raise RuntimeError(f"Coverage escaped source scope: {filename}")
            for line in cls.findall("./lines/line"):
                key = (str(filename), int(line.attrib["number"]))
                lines[key] = lines.get(key, False) or int(line.attrib["hits"]) > 0
    if not lines:
        raise RuntimeError("No executable source lines were measured")
    covered = sum(lines.values())
    message = (
        f"Emitted executable source line coverage: {covered}/{len(lines)} "
        f"({100 * covered / len(lines):.2f}%)\n"
        "Not total-source coverage: Zig omits unanalyzed declarations.\n"
        "Scope: configured Zig test binaries only, not Xcode/UI or other targets.\n"
        f"Raw reports: {run}\n"
    )
    (run / "summary.txt").write_text(message)
    print(message, end="")


if __name__ == "__main__":
    main()
