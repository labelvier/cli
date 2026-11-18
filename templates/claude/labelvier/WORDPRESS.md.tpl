<!-- labelvier-ai-version: 3 -->
# WordPress development

## Theme structure

First check the starterkit version in `package.json` in the project root.

**v7 and up** — the theme splits PHP over `inc/` and `modules/`. Read these before touching theme PHP:

- `wp-content/themes/{theme}/modules/README.md` — the rules: where each kind of code lives, the module contract, how to create one.
- `docs/MODULES.md` — the reasoning behind those rules.

**Below v7** — the inc folder is important because we add controller / service functionality there. If the functionality gets too big you should create a subfolder with namespace and autoload.

Example:
```php
/**
 * Entry point for autoloading AFAS Connector files and classes.
 */

use AFASConnect\Services\VacancyStatusService;
use AFASConnect\Services\VacancySync;

spl_autoload_register(static function ($class_name) {
	// project-specific namespace prefix.
	$prefix = 'AFASConnect\\';

	// base directory for the namespace prefix.
	$base_dir = __DIR__ . '/includes/';

	// does the class use the namespace prefix?
	$len = strlen($prefix);

	// return if not using the prefix
	if (strncmp($prefix, $class_name, $len) !== 0) {
		return;
	}

	$relative_class = substr($class_name, $len);

	$file = $base_dir . str_replace('\\', '/', $relative_class) . '.php';

	// if the file exists, require it.
	if (file_exists($file)) {
		require $file;
	}
});

foreach (glob(__DIR__ . '/*.php') as $file) {
	require_once $file;
}
// Initialize global VacancySync instance
// Initialize vacancy status handling (404 for offline vacancies)
add_action('init', function() {
	// Initialize vacancy status handling (404 for offline vacancies)
	new VacancyStatusService();
	new VacancySync();
});
```

## Docker environment

When working on a Label Vier starter kit WordPress project, the site is running in a Docker environment. When doing checks or running commands, use `npm run` for accessing the Docker environment.

For example, when running a `wp` cli command, run `npm run wp`. If you want to add assoc argument, add an extra -- to escape npm. I.e. `npm run wp -- --info`

Check .env file for the correct ports and urls and other settings.

## Cron jobs

When a project needs a cron job (recurring or delayed background task), prefer Action Scheduler (`as_schedule_recurring_action()`, `as_schedule_single_action()`, `as_enqueue_async_action()`) over WP-Cron (`wp_schedule_event()` / `wp_schedule_single_event()`). Action Scheduler gives queueing, retries, logging and an admin overview. Only fall back to WP-Cron when Action Scheduler is not available and cannot be added as a dependency.

## Testing

Test behaviour, not looks. A change to behaviour or a critical flow is not done without a passing test.

- **Functional Playwright tests are required** when you change something interactive or critical. Examples: navigation and the mobile menu, forms (validation and submit), search, filters, pagination, load more, blocks or modules with JS (accordion, tabs, modal), and flows such as applying for a vacancy, checkout or login. Write or update the test for that behaviour. If the project has no Playwright setup yet, add it first.
- **Smoke test and axe on touched templates.** Each template you changed (home, archive, single, 404, …) loads with status 200, has no console errors and shows an `h1`. It passes axe (`@axe-core/playwright`) and WCAG AA: labels, focus management, contrast.
- **Purely visual changes** (CSS, spacing, a static template tweak) need no test. Check them yourself in the browser at mobile and desktop width, and say that you did.
- **Keep tests independent of content.** The database differs per developer and editors change content. Seed test data with WP-CLI (`npm run wp`), or test structure instead of text. Select with role/label or `data-testid`, never with CSS classes. Specs go in `tests/e2e/`.
- Run the tests against the local Docker site. Take the base URL from `.env`, never a staging or production URL.
- Never hit a live API, mailbox or LLM in the tests. Mock external requests with `page.route()`.
- **Business logic in `inc/` or `modules/`** (integrations such as an AFAS sync, mappers, Action Scheduler jobs) gets PHPUnit tests with the external API mocked. Don't unit-test hooks or templates.
- No visual regression (screenshot) tests by default. Add them only on a fixed styleguide page with static content, run in Docker, and only when the project asks for it.

**Exception: agents with a narrower scope.** When you run as a subagent whose brief excludes tests (for example "only edit this template" or "don't touch `tests/`"), stay inside that scope: don't write or change tests. In your report, list which tests the change needs (or which existing tests it may break), so the caller can add them. The caller still owns the testing requirement.

## Before you finish

1. The project's lint scripts.
2. The Playwright tests, including smoke and axe on touched templates.
3. PHPUnit, if you changed business logic and the project has it.
4. Say plainly what you skipped and why. Don't report work as done with a failing test.
