<!-- labelvier-ai-version: 1 -->
# Laravel development

Applies when `composer.json` requires `laravel/framework`. The project's own `AGENTS.md`, `CLAUDE.md` and `PLAN.md` win over this file: read them first.

## Versions: always the latest

- **New projects** start on the latest stable Laravel and the latest stable release of every package (Livewire, Flux, Tailwind, Pest, Playwright, Vite, …). Look the versions up when you start (`composer create-project laravel/laravel`, `composer show -l`, `npm view <pkg> version`). Never copy older version constraints from another project or from memory.
- **New dependencies** in any project: require the latest stable release, unless it needs a newer Laravel or PHP than the project has. Then say so.
- **Existing projects:** when `composer outdated --direct` or `npm outdated` shows a major behind, say so and offer the upgrade as its own change. Don't mix an upgrade into unrelated work.
- PHP: the newest version Laravel supports that is also available on the hosting (SiteGround).

## Default stack

| Layer | Choice |
| --- | --- |
| Framework | Laravel (latest), PHP (latest supported) |
| Front-end | Livewire + Flux UI **free**, Blade. No Vue, React or Inertia; no Alpine beyond what Livewire/Flux ships |
| CSS | Tailwind CSS via `@tailwindcss/vite`, theming through `@theme` tokens |
| Database | MariaDB in dev and production, SQLite in tests |
| Dev environment | Laravel Sail (mariadb, mailpit) |
| Tests | Pest (unit/feature), Playwright + `@axe-core/playwright` (E2E) |
| Quality | Pint, Larastan |
| Deploy | GitOps: GitHub Actions runs the tests, then Deployer (`recipe/laravel.php`) to SiteGround |

If a task seems to need something outside this list, say so and ask. Don't quietly add a dependency, and never add one with a paid licence.

## Flux UI

- There is **no Flux Pro licence**. Never add `livewire/flux-pro`. Only use components from `livewire/flux`.
- Pro-only components we've hit: `flux:tabs`, `flux:chart`, `flux:editor`. For those, build a small Blade component in `resources/views/components/` with plain Tailwind (keep tab a11y: `role="tablist"`, `aria-selected`, arrow keys). When unsure if a component is Pro, check the Flux docs before using it.
- Free and fine to use: `button`, `input`, `select`, `checkbox`, `switch`, `field`, `modal`, `badge`, `callout`, `card`, `tooltip`, `table`, `pagination`, `menu`, `navlist`, `breadcrumbs`, `toast`, `progress`.
- Prefer Flux components over hand-rolled markup. Theme by overriding tokens in `@theme`, not by stacking utility classes on every Flux component.
- Only add `@fluxAppearance` when the design has a dark mode. It sets `.dark` from the OS preference and changes `--color-accent`.
- Flux ships Heroicons. A design with another icon set gets overrides in `resources/views/flux/icon/`.

## Running commands

Run everything inside the project's environment, never against the host database. Check `AGENTS.md`, `README.md` and the `composer.json`/`package.json` scripts for the wrapper:

- **Sail** (default): `sail up -d`, `sail artisan …`, `sail composer …`, `sail npm …`, `sail test`, `sail bin pint`, `sail bin phpstan analyse`.
- **Laravel inside a WordPress repo** (`backend/` folder, own service in the root `docker-compose.yml`, e.g. `localhost:8080`, with its own DB container): use the root npm scripts, e.g. `npm run backend:artisan -- migrate`, `npm run backend:test`.
- **SQLite projects without Docker**: plain `php artisan …` and `composer dev`.

Playwright runs on the host, against the app URL. Mail in dev lands in Mailpit (`http://localhost:8025`): check it yourself instead of asking whether a mail looks right.

## Architecture

- **Thin controllers and Livewire components.** Business logic goes in `app/Services/` (or `app/Domain/<Domain>/` when the project uses that). Never in Blade views.
- **Livewire 4 and up:** pages are single-file components in `resources/views/pages/{domain}/⚡{name}.blade.php`, registered with `Route::livewire('path', 'pages::domain.name')`. **Livewire 3:** classes in `app/Livewire/`, views in `resources/views/livewire/`. Follow what the project already does.
- Validation via `#[Validate]`, `rules()` or a `FormRequest`. Never write unvalidated input to the DB, never validate in the view.
- Authorisation via policies/gates; call `$this->authorize()` in every write action.
- Fixed sets (statuses, types, roles) are PHP backed enums in `app/Enums/` with a `label()` method that returns a `__()` string. Cast them in `casts()`. No lookup tables for fixed sets.
- Query scopes on the model for reused queries. Eager-load (`with()`) in the component or controller, never in the Blade view. Watch for N+1.
- Filter/sort/page state in Livewire goes in the URL with `#[Url]`.
- API responses always go through a `JsonResource`. Treat the field set as a public contract: when a WordPress plugin or app reads it, change both sides in the same change.
- Config values live in `config/*.php` and are read with `config()`. Never call `env()` outside config files. New `.env` keys also go in `.env.example` with placeholder values.
- Migrations are additive: never edit a migration that has already run, write a new one.
- Files that need access control go on the private disk and out through a controller. Never a public symlink to them.
- External APIs: use Laravel's `Http` client. Keep the request in the client class; map the response into a data class or DTO elsewhere.
- Long or external work (harvesting, syncing, AI calls) runs in queued jobs, not in the request.

## Code style

- PSR-12 via Pint. `declare(strict_types=1)` and typed properties/parameters/return types in new code. In an existing project without strict types, follow the existing convention.
- **Laziest thing that works, then stop.** No interface with one implementation, no factory for one product, no config entry for a value that never changes, no abstraction "for later".
- No `serialize()`: use JSON casts.
- Time: store UTC, display `Europe/Amsterdam`, prefer `CarbonImmutable`. Pass the timezone explicitly when parsing a naive date string.
- Never render user or third-party content with `{!! !!}` unless it was escaped first.
- No secrets in code or commits.
- UI text is Dutch unless the project says otherwise. Code, identifiers, commits and comments are English. Match the surrounding comment density.

## Testing

- Every new route, service, mapper or non-trivial branch gets a Pest test. Trivial one-liners don't.
- Never hit a live API, mailbox, LLM or the internet in the normal suite. Use `Http::fake()` with `Http::preventStrayRequests()` and recorded fixtures in `tests/Fixtures/`. Fake every AI call: no test spends tokens. A deliberate live check goes in `--group=contract`, outside the default run.
- Tests run on SQLite (`:memory:` for Pest, a file database for Playwright), so they need no running database and work in CI/GitOps. Don't write MariaDB-only SQL in app code; when a feature really needs it, put its tests in a separate group.
- Commit a `.env.testing` with test-only values (SQLite, a generated test `APP_KEY`, `array`/`sync` drivers, no real secrets or external URLs). Tests and CI read that file and never need a developer's `.env`. Keep the `phpunit.xml` `<env>` overrides consistent with it.
- Playwright: specs in `tests/e2e/`, page objects in `tests/e2e/pages/`, `data-testid` selectors only (never Tailwind classes). Authenticate once via `storageState`. Run `--update-snapshots` only for an intended visual change.
- A UI change gets or updates a Playwright test. UI must pass axe checks and WCAG AA (labels, focus management, contrast).

## Before you finish

1. Pint (`sail bin pint` or the project's lint script).
2. Larastan, if the project has it.
3. The test suite.
4. Playwright, if you touched `app/Livewire`, `resources/views`, routes or seeders.
5. Say plainly what you skipped and why. Don't report work as done with a failing test.

## Deploy: GitOps

We deploy with GitOps: Git is the source of truth and merging is deploying.

- A push to `develop` (every merged PR) starts a GitHub Actions workflow: it runs the test suite, merges `develop` into `staging` when the tests pass, then deploys with Deployer (`deploy.php`, `recipe/laravel.php`) to SiteGround. A failing test stops the deploy.
- **Initial setup:** when a project is to go live (staging or production) and has no GitOps yet, set it up with `labelvier gitops setup`, not by hand. It creates the deploy key, server folders, `public_html` symlink, GitHub environment and secrets, and runs the first deploy. `labelvier gitops tests` adds the test step, `labelvier gitops status` shows what is in place. Don't hand-write the workflow or `deploy.php` instead.
- No app secrets in CI. GitHub only knows the SSH key and the target; the app `.env` lives on the server. That's why tests use the committed `.env.testing`.
- `labelvier deploy staging` still works for a manual deploy.
- `artisan:queue:restart` must run after the symlink swap, or workers keep running old code.
- SiteGround: the system Node is too old for `npm ci`/Vite. Load the right version via nvm before building.
- Always ask for explicit confirmation before a production deploy.

## Starting a new project

Write a technical plan first: `PLAN.md` (scope, data model, phases, open questions) and a project `AGENTS.md` (stack, commands, layout, conventions, things that will bite you). Wait for approval before building. Don't repeat what this file and `GLOBAL.md` already cover.
