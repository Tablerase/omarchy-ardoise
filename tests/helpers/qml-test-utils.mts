import fs from "node:fs";
import path from "node:path";

export const repoDir = path.resolve(import.meta.dirname, "../..");

/**
 * Extract the brace-balanced body of a named QML handler on the element
 * identified by `anchor`.
 *
 * Braces inside line comments and quoted strings are ignored so the match does
 * not terminate early. A plain non-greedy regex cannot do this: in a handler
 * like
 *
 *   onPositionChanged: { if (!x) { x = true } }
 *   onClicked: { doThing() }
 *
 * the first `}` closes an inner block, not the element.
 */
export function extractHandler(source: string, anchor: string, handler: string): string | null {
  const anchorAt = source.indexOf(anchor);
  if (anchorAt === -1) return null;
  const handlerAt = source.indexOf(handler, anchorAt);
  if (handlerAt === -1) return null;

  const open = source.indexOf("{", handlerAt);
  if (open === -1) return null;

  let depth = 0;
  let inLine = false;
  let inDouble = false;
  let inSingle = false;

  for (let i = open; i < source.length; i++) {
    const c = source[i];
    const next = source[i + 1];

    if (inLine) {
      if (c === "\n") inLine = false;
      continue;
    }
    if (inDouble) {
      if (c === "\\") i++;
      else if (c === '"') inDouble = false;
      continue;
    }
    if (inSingle) {
      if (c === "\\") i++;
      else if (c === "'") inSingle = false;
      continue;
    }

    if (c === "/" && next === "/") {
      inLine = true;
      i++;
      continue;
    }
    if (c === '"') { inDouble = true; continue; }
    if (c === "'") { inSingle = true; continue; }
    if (c === "{") depth++;
    else if (c === "}") {
      depth--;
      if (depth === 0) return source.slice(open + 1, i);
    }
  }
  return null;
}

/**
 * Resolve a binary on PATH without shelling out.
 *
 * `which` is a separate package on Arch and is absent from a bare container,
 * so `execSync("which ...")` fails there for the wrong reason - it looks like
 * the target is missing rather than the lookup tool. Scanning PATH directly
 * is dependency-free and correct in any minimal environment.
 */
export function findOnPath(bin: string): string | null {
  for (const dir of (process.env.PATH || "").split(path.delimiter)) {
    if (!dir) continue;
    const candidate = path.join(dir, bin);
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch {
      // not here; keep looking
    }
  }
  return null;
}
