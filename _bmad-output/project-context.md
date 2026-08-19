---
project_name: 'chatwoot'
user_name: 'TPC'
date: '2026-07-14'
sections_completed:
  ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'code_quality', 'workflow_rules', 'dont_miss_rules']
status: 'complete'
rule_count: 68
optimized_for_llm: true
existing_patterns_found: 12
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

**Backend — Rails monolith**
- Ruby `3.4.4` (manage via `rbenv`; run `eval "$(rbenv init -)"` before any `bundle`/`rspec`)
- Rails `~> 7.1` · PostgreSQL (+ pgvector/neighbor) · Redis
- Sidekiq `7.3` (+ sidekiq-cron) · Puma `7.2` · ActionCable + Wisper dispatcher
- Devise + devise_token_auth + Pundit · flag_shih_tzu (feature flags) · Stripe `~> 18.0`
- Searchkick/Opensearch · pg_search · audited · Liquid · Commonmarker

**Frontend — Vue 3 multi-app SPA**
- Vue `3.5.12` (Composition API + `<script setup>`) · Vite `6.4.2` (via vite_rails + vite-plugin-ruby)
- Vuex `4.1` (legacy — do NOT extend) + Pinia `3.0.4` (new state)
- Vue Router `4.4.5` · Vue I18n `9.14.5` · axios · `@rails/actioncable`
- Tailwind `3.4.19` (the only styling system)
- Node `24.x` · pnpm `10.x` (corepack-pinned `pnpm@10.2.0`)
- 8 Vite entrypoints: dashboard, widget, sdk, portal, v3app, superadmin, survey, v3

**Version constraints / locks agents must respect**
- `vite`/`vitest` are pnpm-overridden to `6.4.2`/`3.0.5` — do not bump ad hoc.
- Vitest must run via `pnpm test*` (enforces `TZ=UTC`); raw `vitest` uses the wrong timezone.
- Bundle budgets (size-limit): widget ≤ 300 KB, `sdk.js` ≤ 40 KB.
- `net-smtp` locked to `~> 0.3.4` (gmail_xoauth2 compat); `minimatch`/`rollup` pinned via overrides.

## Critical Implementation Rules

### Language-Specific Rules

**Ruby**
- Compact `module/class` definitions — no nested `class Foo::Bar` (RuboCop `Style/ClassAndModuleChildren` enforced).
- Raise custom exceptions from `lib/custom_exceptions/` — never bare `raise StandardError`.
- Use strong params in every controller action; never pass `params` directly into model/service calls.
- Prefer `find` / `find_by!` / required hash keys over silent fallbacks for locked/internal production configs — let misconfiguration fail loudly.
- Specs: stub env via `with_modified_env` (climate_control helper), never stub `ENV` directly.
- In parallel/reloading specs, assert `error.class.name` (string), not constant class equality.

**JavaScript / Vue**
- Component files use `<script setup>` Composition API only; block order is `script → template → style` (`vue/block-order`).
- No bare strings in templates — all user-facing text via i18n keys (`vue/no-bare-strings-in-template`).
- `no-v-text` and `no-console` are hard errors.
- Components are PascalCase; custom events are camelCase; declare PropTypes.
- Use ESM `import`/`export`; the bundle is built by Vite (`vite-plugin-ruby`) — do not hand-edit `public/packs/*`.

### Framework-Specific Rules

**Rails (backend)**
- Layered flow: thin controller → service in `app/services/<domain>/` → model + domain event → Wisper listener/job/ActionCable. Put new business logic in a service object, not the controller or model.
- Dispatch domain events via `Rails.configuration.dispatcher`; listeners live in `app/listeners/` (never invoke listeners directly from models).
- Multi-tenancy: scope every query by `account_id`; current account/user comes from the `Current` registry.
- Authorize with Pundit (`app/policies/`); check `enterprise/` for an EE override before editing an OSS policy.
- Background work = Sidekiq jobs in `app/jobs/`; pick the correct queue by priority (`config/sidekiq.yml`: `critical` → … → `low` → `mailers` …).
- Feature flags via `flag_shih_tzu`; some are also reconciled from the billing plan.

**Vue 3 (frontend)**
- New state = a Pinia store (`dashboard/stores/`); Vuex modules (`dashboard/store/`) are legacy — do not extend them.
- New UI goes in `components-next/` (`dashboard/components-next/`); legacy `components/` is deprecated (especially message bubbles).
- Call APIs through the API client (`dashboard/api/`), not ad-hoc axios inside components.
- Realtime via the ActionCable `RoomChannel` client — do not hand-roll WebSocket plumbing.
- i18n messages are per-feature under `dashboard/i18n/locale/en/*.json`; run `pnpm sync:i18n` after editing the locale index.
- Branding: use `replaceInstallationName` from `shared/composables/useBranding` instead of hardcoding "Chatwoot".

### Testing Rules

**Ruby (RSpec)**
- Always run `bundle exec rspec` (never raw `rspec`); Spring is on — run `spring stop` if specs misbehave after edits.
- Use FactoryBot + shoulda-matchers; mock HTTP with `webmock`; validate OpenAPI contracts via `skooma`.
- Prefer `let` values and direct per-example setup — avoid custom spec helper methods.
- Don't write specs unless explicitly asked. Enterprise specs live under `spec/enterprise`, mirroring OSS layout.

**JavaScript (Vitest)**
- Always invoke via `pnpm test` / `pnpm test:watch` — the script forces `TZ=UTC`; raw `vitest` will not.
- Environment: `jsdom`, globals on, pool `threads`. Colocate `*.spec.js` / `*.test.js` next to source under `app/`.
- Setup installs `vue-i18n` + `floating-vue` and stubs `WootModal`, `WootModalHeader`, `NextButton`; IndexedDB is polyfilled via `fake-indexeddb`.
- Stories live in `*.story.vue` next to the component (Histoire, port 6179).

### Code Quality & Style Rules

**Linting / formatting**
- Ruby: RuboCop with **150-char max line length**; custom cops live in `./rubocop/` (`use_from_email`, `custom_cop_location`, `attachment_download`, `one_class_per_file`) — respect them.
- JS/Vue: ESLint extends `airbnb-base/legacy` + Prettier (run as error) + `vue/vue3-recommended`. Prettier: printWidth 80, single quotes, trailing comma `es5`, arrow parens `avoid`.
- Pre-commit (Husky + lint-staged) auto-fixes staged files: `eslint --fix` on `app/**/*.{js,vue}`, `rubocop -a` on `.rb`, `scss-lint` on `.scss`. Do not bypass it.

**Code organization**
- Backend Rails dirs have fixed homes: business logic → `app/services/<domain>/`; authz → `app/policies/`; queries → `app/finders/`; jobs → `app/jobs/`; events → `app/listeners/`; view objects → `app/drops`/`presenters`.
- Frontend apps are self-contained under `app/javascript/<app>/` (`dashboard`, `widget`, `sdk`, `portal`, `v3`, `superadmin_pages`, `survey`); shared code → `app/javascript/shared/`.

**Naming**
- Vue: PascalCase components, camelCase custom events, kebab-case attributes in templates.
- Ruby: snake_case files/symbols; compact module names.

**General engineering**
- Ship the smallest production-ready change that solves the problem; build for the expected production path — no speculative guards, fallbacks, retries, or edge-case handling unless the caller can actually hit it.
- Remove dead/unreachable code; never keep two implementations of the same logic.
- Prefer existing repo dependencies over hand-rolled protocol/parsing/auth/signing code.

### Development Workflow Rules

**Git / branching**
- Work on a feature branch per task — the pre-push hook (`bin/validate_push`) **blocks direct pushes to `master` and `develop`**.
- Conventional Commits only: `type(scope): subject` (e.g. `feat(auth): add user authentication`). Never reference Claude/AI in commit messages.
- For parallel/isolated work use a separate git worktree + branch per task (`.codex/` setup, `Procfile.worktree`); generate per-worktree DB/port/Redis-index values to avoid collisions.

**Local run**
- `pnpm dev` starts overmind: backend `:3000`, sidekiq worker, vite `:3036` (all three must run for HMR).
- DB: `make db` runs the canonical `db:chatwoot_prepare` (create + migrate + schema) — also the Heroku `release` command.
- Copy `.env.example` → `.env` and edit; **never read or commit the real `.env`**. `SECRET_KEY_BASE` must be alphanumeric (symbols break signed cookies).

**Pull requests**
- Open with a short user-facing paragraph describing the product change.
- Include a `Closes` section (issue/Linear links); `How to test` for features or `How to reproduce` for bugfixes; optional `What changed`.
- Do NOT add a "How this was tested" section listing specs/commands.

### Critical Don't-Miss Rules

**Anti-patterns (do NOT)**
- Do NOT extend Vuex (`dashboard/store/`) or legacy `components/` (esp. message bubbles) — use Pinia (`dashboard/stores/`) and `components-next/`.
- Do NOT edit OSS core files for Enterprise-only behavior — use `prepend_mod_with` / `include_mod_with` and place EE code under `enterprise/`; search both `app` and `enterprise` before editing.
- Do NOT hardcode "Chatwoot" in user-facing strings — use `replaceInstallationName` from `shared/composables/useBranding`.
- Do NOT hand-roll WebSocket/HTTP/auth/signing/parsing — use ActionCable `RoomChannel`, `ssrf_filter`, the existing channel-client gems, and `csv-safe`.
- Do NOT write custom/scoped/inline CSS, bare template strings, or stub `ENV` directly.
- Do NOT push to `master`/`develop`, bypass pre-commit hooks, or reference Claude in commits.
- Do NOT add speculative guards, silent fallbacks, or duplicate implementations of existing logic.

**Security / multi-tenancy**
- Every query must be scoped by `account_id` — an unscoped query is a cross-tenant data-leak bug. Authorize every controller action with Pundit (and check for an EE policy override).
- Fetch remote URLs via `ssrf_filter`; sanitize CSV with `csv-safe`; validate JSON payloads with `json_schemer`.
- Never read or commit `.env` or secrets; locked production configs should fail loudly (`find_by!`), not silently fall back.

**Performance / runtime gotchas**
- Watch for N+1 — `bullet` is enabled in dev; eager-load associations.
- Postgres `STATEMENT_TIMEOUT` (default ~14s) will kill slow queries — move heavy work to a Sidekiq job on the correct queue.
- Keep bundle budgets: widget ≤ 300 KB, `sdk.js` ≤ 40 KB.
- Spring caches code — `spring stop` if specs behave oddly after edits.

---

## Usage Guidelines

**For AI Agents:**

- Read this file before implementing any code.
- Follow ALL rules exactly as documented.
- When in doubt, prefer the more restrictive option.
- Update this file if new patterns emerge.

**For Humans:**

- Keep this file lean and focused on agent needs — it complements, not duplicates, `CLAUDE.md` and `docs/`.
- Update when the technology stack or versions change.
- Review periodically for outdated rules; remove rules that have become obvious over time.

_Last Updated: 2026-07-14_
