<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

<!-- BEGIN:nextjs-agent-kit -->

## Project rules for coding agents

These rules point at official Next.js and Vercel sources. They don't restate framework APIs, because those change between versions. If anything here disagrees with the bundled docs, the bundled docs win.

### Where Next.js knowledge comes from

1. `node_modules/next/dist/docs/`: docs for the installed version (Next.js 16.2+).
2. On Next.js 16.1 or earlier: `.next-docs/`, written by `npx @next/codemod@canary agents-md`.
3. Over the network: the index at https://nextjs.org/docs/llms.txt. Add `.md` to any `nextjs.org/docs` URL to get Markdown.
4. Errors: open the `Learn more` link that `next dev` / `next build` prints (`nextjs.org/docs/messages/<id>`). These pages are written for agents and aren't bundled.

Don't write Next.js APIs from memory. Look them up first, and follow deprecation notices.

### Linting and formatting: Biome only

- Biome is the linter, formatter and import sorter. Its config is `biome.json`, with the `next` and `react` domains turned on.
- Check: `biome check` (the `lint` script). Fix: `biome check --write`. Format only: `biome format --write` (the `format` script).
- Don't add ESLint, Prettier, oxlint, or their configs or plugins. `next lint` was removed in Next.js 16, and `next build` no longer lints.
- Don't turn rules off to silence errors. If a suppression is truly needed, write `// biome-ignore <group>/<rule>: <reason>` with a real reason.

### Verify before you report done

- Reuse the running dev server. `next dev` records its URL and PID in `.next/dev/lock`, so don't start a second one.
- While editing, ask the dev server instead of running a full build: Next.js MCP (`next-devtools`) `get_errors`, `get_compilation_issues` and `compile_route`.
- After changing routes or UI, check the change at runtime with the `next-dev-loop` skill.
- Before finishing: run `biome check`. Run `next build` (it also type-checks) when the change touches `next.config.*`, caching, routing, or Server/Client boundaries.

### Upgrades

- Use `npx next upgrade --agent=latest`, or `npx @next/codemod@latest upgrade latest`, and follow the version's upgrade guide in the bundled docs. Don't migrate APIs by hand when a codemod exists.

### Skills (workflows, not reference)

| Task | Skill |
| --- | --- |
| Check a change against the running app | `next-dev-loop` |
| Audit or shrink client bundles | `next-bundle-optimizer` |
| Turn on Cache Components | `next-cache-components-adoption` |
| Grow a route's static shell / instant navigation | `next-cache-components-optimizer` |
| Turn on / tune Partial Prefetching | `next-partial-prefetching-adoption`, `next-partial-prefetching-optimizer` |
| React / Next.js performance review | `vercel-react-best-practices` |
| Component API design | `vercel-composition-patterns` |
| UI, accessibility and UX review | `web-design-guidelines` |

### Managed blocks

Next.js owns the content between the `<!-- BEGIN:nextjs-agent-* -->` and `<!-- END:nextjs-agent-* -->` markers and rewrites it. Don't edit it. Commit the changes `next dev` makes to this file.

<!-- END:nextjs-agent-kit -->
