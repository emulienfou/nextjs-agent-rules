#!/usr/bin/env bash
# Apply the Next.js agent rules kit to a project. Safe to re-run: it updates
# its own block in AGENTS.md and leaves everything else alone.
#
# Usage: scripts/install.sh <project-dir> [--skills] [--agent <name>] [--migrate] [--dry-run]
#   --skills      install the official Next.js and Vercel skills (npx skills add)
#   --agent NAME  target agent for skills (e.g. claude-code, codex, cursor); repeatable
#   --migrate     convert an existing ESLint/Prettier setup with `biome migrate`
#   --dry-run     print what would change, change nothing
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$KIT_DIR/template"

PROJECT=""
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
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) PROJECT="$1" ;;
  esac
  shift
done

[[ -n "$PROJECT" ]] || { echo "usage: $0 <project-dir> [--skills] [--agent NAME] [--migrate] [--dry-run]" >&2; exit 1; }
PROJECT="$(cd "$PROJECT" && pwd)"
[[ -f "$PROJECT/package.json" ]] || { echo "error: no package.json in $PROJECT" >&2; exit 1; }
grep -q '"next"' "$PROJECT/package.json" || echo "warning: package.json does not list \"next\"; in a monorepo, point this at the app folder." >&2

say() { echo "• $*"; }
run() { if [[ $DRY -eq 1 ]]; then echo "  [dry-run] $*"; else "$@"; fi; }

# Package manager, from the lockfile.
if   [[ -f "$PROJECT/pnpm-lock.yaml" ]]; then PM=pnpm; ADD=(pnpm add -D -E); X=(pnpm exec)
elif [[ -f "$PROJECT/yarn.lock" ]];      then PM=yarn; ADD=(yarn add -D -E); X=(yarn)
elif [[ -f "$PROJECT/bun.lock" || -f "$PROJECT/bun.lockb" ]]; then PM=bun; ADD=(bun add -d --exact); X=(bunx)
else PM=npm; ADD=(npm install -D -E); X=(npx)
fi
say "package manager: $PM"

# 1. AGENTS.md: replace our block if it is there, otherwise add it. Next.js's
#    managed block is added only if missing; `next dev` keeps it current.
KIT_BLOCK="$(awk '/<!-- BEGIN:nextjs-agent-kit -->/,/<!-- END:nextjs-agent-kit -->/' "$TEMPLATE/AGENTS.md")"
NEXT_BLOCK="$(awk '/<!-- BEGIN:nextjs-agent-rules -->/,/<!-- END:nextjs-agent-rules -->/' "$TEMPLATE/AGENTS.md")"
AGENTS_MD="$PROJECT/AGENTS.md"
if [[ ! -f "$AGENTS_MD" ]]; then
  say "AGENTS.md: create"
  run cp "$TEMPLATE/AGENTS.md" "$AGENTS_MD"
else
  if [[ $DRY -eq 1 ]]; then
    say "AGENTS.md: update kit block (other content kept)"
  else
    KIT_BLOCK="$KIT_BLOCK" NEXT_BLOCK="$NEXT_BLOCK" node -e '
      const fs = require("fs"); const f = process.argv[1];
      let s = fs.readFileSync(f, "utf8");
      const kit = process.env.KIT_BLOCK, nxt = process.env.NEXT_BLOCK;
      const re = /<!-- BEGIN:nextjs-agent-kit -->[\s\S]*?<!-- END:nextjs-agent-kit -->/;
      if (!s.includes("<!-- BEGIN:nextjs-agent-rules -->")) s = nxt + "\n\n" + s;
      s = re.test(s) ? s.replace(re, kit) : s.replace(/\s*$/, "\n\n") + kit + "\n";
      fs.writeFileSync(f, s);
    ' "$AGENTS_MD"
    say "AGENTS.md: kit block updated, other content kept"
  fi
fi

# 2. CLAUDE.md: Claude Code reads CLAUDE.md, so it imports AGENTS.md.
if [[ ! -f "$PROJECT/CLAUDE.md" ]]; then
  say "CLAUDE.md: create (imports AGENTS.md)"
  run cp "$TEMPLATE/CLAUDE.md" "$PROJECT/CLAUDE.md"
elif ! grep -q '@AGENTS.md' "$PROJECT/CLAUDE.md"; then
  say "CLAUDE.md: add @AGENTS.md import at the top"
  [[ $DRY -eq 1 ]] || { printf '@AGENTS.md\n\n' | cat - "$PROJECT/CLAUDE.md" > "$PROJECT/CLAUDE.md.tmp" && mv "$PROJECT/CLAUDE.md.tmp" "$PROJECT/CLAUDE.md"; }
fi

# 3. .mcp.json: add the next-devtools server, keep other servers.
say ".mcp.json: ensure next-devtools server"
[[ $DRY -eq 1 ]] || node -e '
  const fs = require("fs"); const f = process.argv[1], t = process.argv[2];
  const cur = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : {};
  const add = JSON.parse(fs.readFileSync(t, "utf8"));
  cur.mcpServers = { ...(cur.mcpServers || {}), ...add.mcpServers };
  fs.writeFileSync(f, JSON.stringify(cur, null, 2) + "\n");
' "$PROJECT/.mcp.json" "$TEMPLATE/.mcp.json"

# 4. Biome: install, config, scripts.
cd "$PROJECT"
say "install @biomejs/biome (exact version)"
run "${ADD[@]}" @biomejs/biome

if [[ $MIGRATE -eq 1 ]]; then
  say "convert existing ESLint / Prettier config into biome.json"
  [[ -f biome.json || -f biome.jsonc ]] || run cp "$TEMPLATE/biome.json" biome.json
  run "${X[@]}" biome migrate eslint --write || true
  run "${X[@]}" biome migrate prettier --write || true
fi

if [[ -f biome.json || -f biome.jsonc ]]; then
  say "biome.json exists: kept (compare with template/biome.json)"
else
  say "biome.json: create from the create-next-app template"
  run cp "$TEMPLATE/biome.json" biome.json
fi
# Match the config schema to the installed Biome version.
run "${X[@]}" biome migrate --write || true

say "package.json: lint = biome check, format = biome format --write"
[[ $DRY -eq 1 ]] || node -e '
  const fs = require("fs"); const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
  p.scripts = { ...(p.scripts || {}), lint: "biome check", format: "biome format --write" };
  fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");
'

# 5. Skills (optional). Writes skills-lock.json: commit it.
if [[ $WITH_SKILLS -eq 1 ]]; then
  say "install official Next.js skills"
  run npx -y skills add vercel/next.js --skill '*' "${AGENTS[@]}" -y
  say "install Vercel skills"
  run npx -y skills add vercel-labs/agent-skills \
    --skill vercel-react-best-practices \
    --skill vercel-composition-patterns \
    --skill web-design-guidelines "${AGENTS[@]}" -y
fi

# 6. Report what is left for a person to decide.
LEFT=$(node -e '
  const p = require("./package.json"); const d = { ...p.dependencies, ...p.devDependencies };
  console.log(Object.keys(d).filter(n => /^(eslint|prettier|oxlint)(-|$)|^@typescript-eslint\/|^eslint-(config|plugin)-|^@eslint\/|^@next\/eslint/.test(n)).join(" "));
')
CFG=$(ls -a | grep -E '^(\.eslintrc.*|eslint\.config\..*|\.prettierrc.*|prettier\.config\..*|\.prettierignore|\.eslintignore|\.oxlintrc.*)$' || true)
if [[ -n "$LEFT" || -n "$CFG" ]]; then
  echo
  echo "Still present (remove once Biome passes; nothing was deleted):"
  [[ -n "$LEFT" ]] && echo "  packages: $LEFT"
  [[ -n "$CFG" ]] && echo "  files:    $(echo $CFG)"
fi

echo
echo "Done. Next: run '$PM run lint', start 'next dev' once from your agent so Next.js refreshes AGENTS.md, then commit."
