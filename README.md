# Next.js agent rules

Rules for AI coding agents (Claude Code, Codex, Cursor, Copilot) working on Next.js apps, using only official Next.js and Vercel sources, with Biome as the one linter and formatter.

## Why this repo is small

The Next.js team's own guidance is to **not** keep a hand-written copy of framework rules:

> Framework knowledge comes from the bundled docs, not from Skills.
> — [How Next.js supports AI coding agents](https://nextjs.org/docs/app/guides/ai-agents)

Since 16.2, Next.js ships its docs for the installed version inside `node_modules/next/dist/docs/`. Since 16.3, `next dev` writes a managed block in `AGENTS.md` that points agents at them. In [Vercel's tests](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals), always-loaded docs passed 100% of tasks and skills at most 79%. A rule file that restates APIs (caching defaults, `middleware` vs `proxy`, `revalidateTag`'s arguments) goes stale with every release, and that's exactly where third-party rule sets go wrong.

So this kit doesn't restate the framework. It only:

1. keeps the official managed block in `AGENTS.md` and adds a short project section that points at official sources,
2. sets up Biome the way `create-next-app` does,
3. connects the official Next.js MCP server,
4. installs the official Next.js skills and a few Vercel skills.

## What's included

| File | Copied to | Source |
| --- | --- | --- |
| `template/AGENTS.md` | `AGENTS.md` | Managed block copied word for word from `create-next-app`, plus a kit block between `nextjs-agent-kit` markers |
| `template/CLAUDE.md` | `CLAUDE.md` | `@AGENTS.md`, so Claude Code loads the same rules |
| `template/biome.json` | `biome.json` | [`create-next-app` Biome template](https://github.com/vercel/next.js/blob/canary/packages/create-next-app/templates/app-tw/ts/biome.json) (`next` + `react` domains) |
| `template/.mcp.json` | `.mcp.json` (merged; run with your package manager) | [Next.js MCP guide](https://nextjs.org/docs/app/guides/mcp) |
| `scripts/install.sh` | — | Applies all of the above to a project |

### Skills (`--skills`)

From [`vercel/next.js/skills`](https://github.com/vercel/next.js/tree/canary/skills) (all of them):
`next-dev-loop`, `next-bundle-optimizer`, `next-cache-components-adoption`, `next-cache-components-optimizer`, `next-partial-prefetching-adoption`, `next-partial-prefetching-optimizer`.

From [`vercel-labs/agent-skills`](https://github.com/vercel-labs/agent-skills):
`vercel-react-best-practices`, `vercel-composition-patterns`, `web-design-guidelines`.

Not installed by default, but worth adding if you deploy on Vercel: `deploy-to-vercel`, `vercel-optimize`.

The old `vercel-labs/next-skills` (`next-best-practices`, `next-upgrade`) is retired. Its content now lives in the bundled docs and codemods.

## Use it in a project

```bash
git clone https://github.com/emulienfou/nextjs-agent-rules ~/nextjs-agent-rules
```

```bash
~/nextjs-agent-rules/scripts/install.sh ../my-app --dry-run
```

```bash
~/nextjs-agent-rules/scripts/install.sh ../my-app --skills --agent claude-code --migrate
```

Flags:

- `--skills`: install the skills above. This writes `skills-lock.json`; commit it so teammates get the same skills.
- `--agent <name>`: which agent to install skills for (`claude-code`, `codex`, `cursor`, …). Repeat it for several agents.
- `--migrate`: turn existing ESLint/Prettier settings into `biome.json` with `biome migrate eslint|prettier`.
- `--dry-run`: show the plan, change nothing.

The script never deletes anything. At the end it lists any ESLint/Prettier/oxlint packages and config files still there, for you to remove once `lint` passes.

### Package manager

The script uses the project's own package manager, never npm by default. It reads the root `package.json` `packageManager` field, then the lockfile (`pnpm-lock.yaml`, `yarn.lock`, `bun.lock` / `bun.lockb`, otherwise npm). Biome is installed with it (`pnpm add -D -E`, `yarn add -D -E`, `bun add -d --exact`, `npm install -D -E`). Skills and the MCP server run through its runner: `pnpm dlx`, `yarn dlx` (Yarn 2+), `bunx`, or `npx` (npm and Yarn 1).

### Monorepos

Point the script at the monorepo root or at any folder inside it. It finds the root by walking up to the `pnpm-workspace.yaml`, or to the `package.json` with `workspaces`. Then it writes everything once, at the root:

- `AGENTS.md`, `CLAUDE.md` and `.mcp.json`.
- `biome.json`, with its ignores widened to every package (`!**/node_modules`, `!**/.next`, …), plus `@biomejs/biome` and the `lint` / `format` scripts in the root `package.json` (`pnpm add -w` / `yarn add -W` where needed).
- Skills and `skills-lock.json`.

The root `AGENTS.md` gets only the kit block. Its docs pointer lists each Next.js app's `node_modules/next/dist/docs/`, because with pnpm `next` is often not visible from the root. An app is a workspace package that lists `next` and has a `next.config.*` or a `next dev` / `next build` script, so a UI library with `next` as a peer dependency doesn't count. `next dev` still writes its own managed block in each app's `AGENTS.md`. That's expected, so commit it. Set [`agentRules: false`](https://nextjs.org/docs/app/api-reference/config/next-config-js/agentRules) in an app's `next.config` if you don't want it.

The final report also lists, for each app, a leftover `biome.json` or `.mcp.json`, or a `lint` script that doesn't run Biome. The root `lint` now covers those apps.

## Requirements

- **Next.js 16.3+** for everything. On 16.2 the docs are bundled but `AGENTS.md` isn't kept up to date for you. On 16.1 or earlier, run `npx @next/codemod@canary agents-md` (or upgrade with `npx @next/codemod@latest upgrade latest`).
- Node.js 22.20+ for the `skills` CLI.

## Updating

Re-run `install.sh`. It replaces only the kit block in `AGENTS.md`, adds missing `.mcp.json` entries and resets the `lint` / `format` scripts. Next.js keeps its own block current every time `next dev` runs. Update skills with `<pm> dlx skills update` (`npx skills update` on npm).

## Sources

- [How Next.js supports AI coding agents](https://nextjs.org/docs/app/guides/ai-agents)
- [`agentRules`](https://nextjs.org/docs/app/api-reference/config/next-config-js/agentRules) · [`agentFeedback`](https://nextjs.org/docs/app/api-reference/config/next-config-js/agentFeedback)
- [Next.js MCP server](https://nextjs.org/docs/app/guides/mcp)
- [Installation: set up linting (ESLint or Biome)](https://nextjs.org/docs/app/getting-started/installation#set-up-linting)
- [Upgrading to v16](https://nextjs.org/docs/app/guides/upgrading/version-16)
- [Docs index: `llms.txt`](https://nextjs.org/docs/llms.txt)
- [Next.js agent evals](https://nextjs.org/evals)
- [`skills` CLI](https://github.com/vercel-labs/skills)

## License

MIT
