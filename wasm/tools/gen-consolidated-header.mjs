#!/usr/bin/env node
// Generate wasm/include/ghostty-vt.h: the single-file public API surface of
// libghostty-vt, trimmed to declarations that actually live under
// include/ghostty/.
//
// Method: run the C preprocessor over a translation unit that just includes
// <ghostty/vt.h>, then keep only the regions whose originating file is one of
// libghostty-vt's own headers. System headers (and the standard-library
// include directives the ghostty headers rely on) are dropped and re-emitted
// as a fixed prelude, so the result is self-contained and compiles standalone.
//
// Using the compiler itself as the extractor is deliberate: it cannot drift
// from the real headers the way a hand-maintained copy would. Regenerate with
//   node wasm/tools/gen-consolidated-header.mjs
// Verified by wasm/tools/verify-header.sh (standalone compile + symbol diff).

import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, readFileSync, unlinkSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..", "..");
const includeDir = join(repoRoot, "include");
const outDir = join(repoRoot, "wasm", "include");
const outFile = join(outDir, "ghostty-vt.h");

/** Header prefix carried over verbatim into the consolidated output. */
const PRELUDE = `/* Khostty: consolidated public API surface of libghostty-vt.
 *
 * Generated from include/ghostty/vt*.h by
 * wasm/tools/gen-consolidated-header.mjs -- do not edit by hand.
 *
 * This is the complete public C ABI of libghostty-vt in a single file, with
 * no intra-library #include graph. A consumer only needs this header plus a
 * libghostty-vt binary (static, shared, or the wasm32 module).
 *
 * Regenerate:  node wasm/tools/gen-consolidated-header.mjs
 * Verify:      wasm/tools/verify-header.sh
 */
#ifndef KHOSTTY_VT_H
#define KHOSTTY_VT_H

#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Re-emitted from include/ghostty/vt/types.h, which the preprocessor would
 * otherwise have expanded away. Keep this in sync with that header. */
#ifndef GHOSTTY_API
#if defined(GHOSTTY_STATIC)
  #define GHOSTTY_API
#elif defined(_WIN32) || defined(_WIN64)
  #ifdef GHOSTTY_BUILD_SHARED
    #define GHOSTTY_API __declspec(dllexport)
  #else
    #define GHOSTTY_API __declspec(dllimport)
  #endif
#elif defined(__GNUC__) && __GNUC__ >= 4
  #define GHOSTTY_API __attribute__((visibility("default")))
#else
  #define GHOSTTY_API
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif
`;

const EPILOGUE = `
#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* KHOSTTY_VT_H */
`;

/** Line-marker forms emitted by clang: `# 12 "path" [flags]` and `#line`. */
const LINE_MARKER = /^\s*#\s*(?:line\s+)?(\d+)\s+"((?:[^"\\]|\\.)*)"(?:\s+.*)?$/;

/** True if a preprocessor "current file" belongs to libghostty-vt. */
function isLibHeader(file) {
  const norm = file.replace(/\\/g, "/");
  return norm.startsWith("include/ghostty/") || norm.startsWith(includeDir + "/");
}

function preprocess() {
  const probe = join(here, ".probe.c");
  const out = join(here, ".probe.i");
  writeFileSync(probe, "#include <ghostty/vt.h>\n");
  try {
    execFileSync(
      "zig",
      ["cc", "-E", "-D__wasm__", "-I", includeDir, "-x", "c", "-o", out, probe],
      { cwd: repoRoot, stdio: ["ignore", "inherit", "inherit"] },
    );
    return readFileSync(out, "utf8");
  } finally {
    for (const f of [probe, out]) {
      try {
        unlinkSync(f);
      } catch {
        /* best effort */
      }
    }
  }
}

/**
 * The preprocessor expands GHOSTTY_API to its platform attribute. Put the
 * symbolic name back so the consolidated header reads like the originals.
 */
function restoreApiMacro(text) {
  return text
    .replace(/__attribute__\(\(visibility\("default"\)\)\)\s+/g, "GHOSTTY_API ")
    .replace(
      /__declspec\((?:dllexport|dllimport)\)\s+/g,
      "GHOSTTY_API ",
    );
}

/**
 * Keep only lines originating from libghostty-vt headers, grouped by source
 * header. Include guards already guarantee each header is emitted exactly
 * once, so no cross-header deduplication is needed (and would be harmful:
 * identical-looking `typedef enum {` openers must all survive).
 */
function extract(text) {
  const perFile = new Map();
  let current = null;
  for (const line of text.split("\n")) {
    const marker = line.match(LINE_MARKER);
    if (marker) {
      current = isLibHeader(marker[2]) ? marker[2] : null;
      continue;
    }
    if (current === null) continue;
    if (line.trim() === "") continue;
    if (!perFile.has(current)) perFile.set(current, []);
    perFile.get(current).push(line.replace(/\s+$/, ""));
  }
  return perFile;
}

function render(perFile) {
  const sections = [];
  for (const [file, rawLines] of perFile) {
    const kept = restoreApiMacro(rawLines.join("\n")).split("\n");
    if (kept.length === 0) continue;
    const header = relative(repoRoot, join(repoRoot, file)).replace(/\\/g, "/");
    const rule = "/* " + "-".repeat(66) + " */";
    const label = `/* from ${header}`;
    const pad = Math.max(1, 70 - label.length);
    sections.push(
      [rule, `${label}${" ".repeat(pad)}*/`, rule, kept.join("\n")].join("\n"),
    );
  }
  return sections.join("\n\n");
}

const raw = preprocess();
const extracted = extract(raw);
const body = render(extracted);
const output = `${PRELUDE}\n${body}\n${EPILOGUE}`;

mkdirSync(outDir, { recursive: true });
writeFileSync(outFile, output);

const headers = [...extracted.keys()];
const decls = (output.match(/^GHOSTTY_API\b/gm) || []).length;
console.log(
  `wrote ${relative(repoRoot, outFile)}: ${output.split("\n").length} lines, ` +
    `${headers.length} source headers, ${decls} GHOSTTY_API declarations`,
);
