#!/usr/bin/env bash
# Apply the Next.js agent rules kit to a project. Safe to re-run: it updates
# its own block in AGENTS.md and leaves everything else alone.
#
# Usage: scripts/install.sh <project-dir> [--skills] [--agent <name>] [--migrate] [--dry-run]
#   <project-dir> a Next.js app, or a monorepo (its root or any folder in it)
#   --skills      install the official Next.js and Vercel skills
#   --agent NAME  target agent for skills (e.g. claude-code, codex, cursor); repeatable
#   --migrate     convert an existing ESLint/Prettier setup with `biome migrate`
#   --dry-run     print what would change, change nothing
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$KIT_DIR/template"

TARGET=""
WITH_SKILLS=0
MIGRATE=0
DRY=0
AGENTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skills) WITH_SKILLS=1 ;;
    --agent) AGENTS+=("-a" "$2"); shift ;;
    --migrate) MIGRATE=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) TARGET="$1" ;;
  esac
  shift
done

[[ -n "$TARGET" ]] || { echo "usage: $0 <project-dir> [--skills] [--agent NAME] [--migrate] [--dry-run]" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
[[ -f "$TARGET/package.json" ]] || { echo "error: no package.json in $TARGET" >&2; exit 1; }

say() { echo "• $*"; }
run() { if [[ $DRY -eq 1 ]]; then echo "  [dry-run] $*"; else "$@"; fi; }

# A monorepo root has pnpm-workspace.yaml, or a package.json with "workspaces"
# (npm, yarn, bun).
is_workspace_root() {
  [[ -f "$1/pnpm-workspace.yaml" ]] && return 0
  [[ -f "$1/package.json" ]] && node -e 'process.exit(require(process.argv[1]).workspaces ? 0 : 1)' "$1/package.json" 2>/dev/null
}

# 0. Where to install: the monorepo root if TARGET is inside one, else TARGET.
ROOT="$TARGET"
MONO=0
dir="$TARGET"
while :; do
  if is_workspace_root "$dir"; then ROOT="$dir"; MONO=1; break; fi
  [[ "$dir" == "/" || -d "$dir/.git" ]] && break
  dir="$(dirname "$dir")"
done

has_next() { grep -q '"next"[[:space:]]*:' "$1/package.json"; }
# An app, not a library that only depends on `next`: it has a next.config.* or
# runs `next dev` / `next build`.
is_next_app() {
  has_next "$1" || return 1
  ls "$1"/next.config.* >/dev/null 2>&1 && return 0
  node -e 'const s = require(process.argv[1]).scripts || {}; process.exit(Object.values(s).some(v => /\bnext (dev|build|start)\b/.test(v)) ? 0 : 1)' "$1/package.json"
}

# Next.js apps in a monorepo: every workspace package that is a Next.js app.
APPS=()
if [[ $MONO -eq 1 ]]; then
  while IFS= read -r pj; do
    d="$(dirname "$pj")"
    [[ "$d" != "$ROOT" ]] && is_next_app "$d" && APPS+=("${d#"$ROOT"/}")
  done < <(find "$ROOT" -maxdepth 4 \( -name node_modules -o -name .next -o -name .git -o -name dist -o -name build \) -prune -o -name package.json -print | sort)
  say "monorepo root: $ROOT"
  if [[ ${#APPS[@]} -gt 0 ]]; then say "Next.js apps: ${APPS[*]}"; else echo "warning: no workspace package lists \"next\"." >&2; fi
else
  has_next "$ROOT" || echo "warning: package.json does not list \"next\"." >&2
fi

# Package manager: the root's `packageManager` field, then its lockfile.
PM=""; PM_MAJOR=""
spec="$(node -p 'require(process.argv[1]).packageManager || ""' "$ROOT/package.json")"
if [[ -n "$spec" ]]; then PM="${spec%%@*}"; PM_MAJOR="$(echo "${spec#*@}" | cut -d. -f1)"; fi
if [[ -z "$PM" ]]; then
  if   [[ -f "$ROOT/pnpm-lock.yaml" || -f "$ROOT/pnpm-workspace.yaml" ]]; then PM=pnpm
  elif [[ -f "$ROOT/yarn.lock" ]]; then PM=yarn
  elif [[ -f "$ROOT/bun.lock" || -f "$ROOT/bun.lockb" ]]; then PM=bun
  else PM=npm
  fi
fi
YARN_BERRY=0
if [[ "$PM" == yarn ]]; then
  if [[ -n "$PM_MAJOR" ]]; then [[ "$PM_MAJOR" -ge 2 ]] && YARN_BERRY=1
  elif [[ -f "$ROOT/.yarnrc.yml" ]]; then YARN_BERRY=1
  fi
fi

# ADD: install a dev dependency at the root. X: run a local binary.
# DLX: run a package without installing it. MCP: the same, for .mcp.json, with
# the package manager's own output kept off stdout (MCP talks over stdout).
case "$PM" in
  pnpm) ADD=(pnpm add -D -E); [[ $MONO -eq 1 ]] && ADD+=(-w)
        X=(pnpm exec); DLX=(pnpm dlx); MCP='["pnpm", ["--silent", "dlx", "next-devtools-mcp@latest"]]' ;;
  yarn) ADD=(yarn add -D -E); X=(yarn)
        if [[ $YARN_BERRY -eq 1 ]]; then DLX=(yarn dlx); MCP='["yarn", ["dlx", "-q", "next-devtools-mcp@latest"]]'
        else [[ $MONO -eq 1 ]] && ADD+=(-W); DLX=(npx -y); MCP='["npx", ["-y", "next-devtools-mcp@latest"]]'  # yarn 1 has no dlx
        fi ;;
  bun)  ADD=(bun add -d --exact); X=(bunx); DLX=(bunx); MCP='["bunx", ["next-devtools-mcp@latest"]]' ;;
  *)    PM=npm; ADD=(npm install -D -E); X=(npx); DLX=(npx -y); MCP='["npx", ["-y", "next-devtools-mcp@latest"]]' ;;
esac
say "package manager: $PM$([[ "$PM" == yarn ]] && { [[ $YARN_BERRY -eq 1 ]] && echo " (berry)" || echo " (classic)"; })"

# 1. AGENTS.md: replace our block if it is there, otherwise add it.
#    Single app: Next.js's managed block is added only if missing; `next dev`
#    keeps it current. Monorepo: `next dev` writes that block in each app's own
#    AGENTS.md, so the root gets only the kit block, pointing at each app's docs.
APPS_LIST="$(printf '%s\n' ${APPS[@]+"${APPS[@]}"})"
KIT_BLOCK="$(MONO=$MONO APPS_LIST="$APPS_LIST" node -e '
  const fs = require("fs");
  const t = fs.readFileSync(process.argv[1], "utf8");
  let kit = t.match(/<!-- BEGIN:nextjs-agent-kit -->[\s\S]*?<!-- END:nextjs-agent-kit -->/)[0];
  const apps = (process.env.APPS_LIST || "").split("\n").filter(Boolean);
  if (process.env.MONO === "1") {
    const where = apps.length
      ? apps.map(a => "`" + a + "/node_modules/next/dist/docs/`").join(", ")
      : "`<app>/node_modules/next/dist/docs/`";
    kit = kit.replace(
      /^1\. `node_modules\/next\/dist\/docs\/`:.*$/m,
      "1. " + where + ": docs for the Next.js version each app installs (16.2+). This is a monorepo: `next` may not be visible from the repo root, so read the docs of the app you are changing. `next dev` also writes its own block in each app'"'"'s `AGENTS.md`."
    );
  }
  process.stdout.write(kit);
' "$TEMPLATE/AGENTS.md")"
NEXT_BLOCK="$(awk '/<!-- BEGIN:nextjs-agent-rules -->/,/<!-- END:nextjs-agent-rules -->/' "$TEMPLATE/AGENTS.md")"
[[ $MONO -eq 1 ]] && NEXT_BLOCK=""

AGENTS_MD="$ROOT/AGENTS.md"
if [[ -f "$AGENTS_MD" ]]; then
  say "AGENTS.md: update kit block (other content kept)"
else
  say "AGENTS.md: create$([[ $MONO -eq 1 ]] && echo " at the monorepo root (kit block only)")"
fi
[[ $DRY -eq 1 ]] || KIT_BLOCK="$KIT_BLOCK" NEXT_BLOCK="$NEXT_BLOCK" node -e '
  const fs = require("fs"); const f = process.argv[1];
  let s = fs.existsSync(f) ? fs.readFileSync(f, "utf8") : "";
  const kit = process.env.KIT_BLOCK, nxt = process.env.NEXT_BLOCK;
  const re = /<!-- BEGIN:nextjs-agent-kit -->[\s\S]*?<!-- END:nextjs-agent-kit -->/;
  if (nxt && !s.includes("<!-- BEGIN:nextjs-agent-rules -->")) s = nxt + (s ? "\n\n" + s : "");
  s = re.test(s) ? s.replace(re, kit) : (s ? s.replace(/\s*$/, "\n\n") : "") + kit + "\n";
  fs.writeFileSync(f, s);
' "$AGENTS_MD"

# 2. CLAUDE.md: Claude Code reads CLAUDE.md, so it imports AGENTS.md.
if [[ ! -f "$ROOT/CLAUDE.md" ]]; then
  say "CLAUDE.md: create (imports AGENTS.md)"
  run cp "$TEMPLATE/CLAUDE.md" "$ROOT/CLAUDE.md"
elif ! grep -q '@AGENTS.md' "$ROOT/CLAUDE.md"; then
  say "CLAUDE.md: add @AGENTS.md import at the top"
  [[ $DRY -eq 1 ]] || { printf '@AGENTS.md\n\n' | cat - "$ROOT/CLAUDE.md" > "$ROOT/CLAUDE.md.tmp" && mv "$ROOT/CLAUDE.md.tmp" "$ROOT/CLAUDE.md"; }
else
  say "CLAUDE.md: already imports AGENTS.md"
fi

# 3. .mcp.json: add the next-devtools server, run with the package manager,
#    keep other servers.
say ".mcp.json: ensure next-devtools server ($(node -p 'const [c, a] = JSON.parse(process.argv[1]); [c, ...a].join(" ")' "$MCP"))"
[[ $DRY -eq 1 ]] || MCP="$MCP" node -e '
  const fs = require("fs"); const f = process.argv[1];
  const cur = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : {};
  const [command, args] = JSON.parse(process.env.MCP);
  cur.mcpServers = { ...(cur.mcpServers || {}), "next-devtools": { command, args } };
  fs.writeFileSync(f, JSON.stringify(cur, null, 2) + "\n");
' "$ROOT/.mcp.json"

# 4. Biome: install, config and scripts, all at the root.
cd "$ROOT"
say "install @biomejs/biome (exact version)$([[ $MONO -eq 1 ]] && echo " at the workspace root")"
run "${ADD[@]}" @biomejs/biome

# The template's ignores name root folders; a monorepo root also needs every
# app's node_modules/.next/dist/build ignored.
write_biome() {
  if [[ $MONO -eq 1 ]]; then
    [[ $DRY -eq 1 ]] && { echo "  [dry-run] write biome.json (template, ignores widened to every package: !**/node_modules, !**/.next, ...)"; return 0; }
    node -e '
      const fs = require("fs"); const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      c.files.includes = c.files.includes.map(p => p.startsWith("!") && !p.startsWith("!**/") ? "!**/" + p.slice(1) : p);
      fs.writeFileSync("biome.json", JSON.stringify(c, null, 2) + "\n");
    ' "$TEMPLATE/biome.json"
  else
    run cp "$TEMPLATE/biome.json" biome.json
  fi
}

if [[ -f biome.json || -f biome.jsonc ]]; then
  say "biome.json exists: kept (compare with template/biome.json)"
else
  say "biome.json: create from the create-next-app template"
  write_biome
fi

if [[ $MIGRATE -eq 1 ]]; then
  say "convert existing ESLint / Prettier config into biome.json"
  run "${X[@]}" biome migrate eslint --write || true
  run "${X[@]}" biome migrate prettier --write || true
fi
# Match the config schema to the installed Biome version.
run "${X[@]}" biome migrate --write || true

say "package.json: lint = biome check, format = biome format --write"
[[ $DRY -eq 1 ]] || node -e '
  const fs = require("fs"); const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
  p.scripts = { ...(p.scripts || {}), lint: "biome check", format: "biome format --write" };
  fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");
'

# Biome lints JSON and Markdown too: format what this script wrote, so the
# first `lint` passes.
run "${X[@]}" biome format --write AGENTS.md .mcp.json biome.json package.json || true

# 5. Skills (optional), at the root. Writes skills-lock.json: commit it.
if [[ $WITH_SKILLS -eq 1 ]]; then
  say "install official Next.js skills"
  run "${DLX[@]}" skills add vercel/next.js --skill '*' ${AGENTS[@]+"${AGENTS[@]}"} -y
  say "install Vercel skills"
  run "${DLX[@]}" skills add vercel-labs/agent-skills \
    --skill vercel-react-best-practices \
    --skill vercel-composition-patterns \
    --skill web-design-guidelines ${AGENTS[@]+"${AGENTS[@]}"} -y
fi

# 6. Report what is left for a person to decide, at the root and in each app.
leftovers() {
  local d="$1" label="$2" pkgs cfg lint=""
  pkgs=$(node -e '
    const p = require(process.argv[1]); const d = { ...p.dependencies, ...p.devDependencies };
    console.log(Object.keys(d).filter(n => /^(eslint|prettier|oxlint)(-|$)|^@typescript-eslint\/|^eslint-(config|plugin)-|^@eslint\/|^@next\/eslint/.test(n)).join(" "));
  ' "$d/package.json")
  cfg=$(ls -a "$d" | grep -E '^(\.eslintrc.*|eslint\.config\..*|\.prettierrc.*|prettier\.config\..*|\.prettierignore|\.eslintignore|\.oxlintrc.*)$' || true)
  if [[ "$d" != "$ROOT" ]]; then
    # In a monorepo these belong at the root now.
    cfg="$cfg $(ls -a "$d" | grep -E '^(biome\.jsonc?|\.mcp\.json)$' || true)"
    if node -e 'const s = require(process.argv[1]).scripts || {}; process.exit(s.lint && !/biome/.test(s.lint) ? 0 : 1)' "$d/package.json"; then
      lint="$(node -p 'require(process.argv[1]).scripts.lint' "$d/package.json")"
    fi
  fi
  cfg="$(echo $cfg)"
  if [[ -n "$pkgs" || -n "$cfg" || -n "$lint" ]]; then
    echo "  $label:"
    if [[ -n "$pkgs" ]]; then echo "    packages: $pkgs"; fi
    if [[ -n "$cfg" ]]; then echo "    files:    $cfg"; fi
    if [[ -n "$lint" ]]; then echo "    lint:     \"$lint\" (the root lint now runs Biome on every package)"; fi
  fi
  return 0
}
REPORT="$(leftovers "$ROOT" "$([[ $MONO -eq 1 ]] && echo root || echo .)"; for a in ${APPS[@]+"${APPS[@]}"}; do leftovers "$ROOT/$a" "$a"; done)"
if [[ -n "$REPORT" ]]; then
  echo
  echo "Still present (remove once Biome passes; nothing was deleted):"
  echo "$REPORT"
fi

echo
echo "Done. Next: run '$PM run lint' in $ROOT, start 'next dev' once from your agent so Next.js refreshes AGENTS.md, then commit."
