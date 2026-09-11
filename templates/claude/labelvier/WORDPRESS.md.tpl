# WordPress development

## Docker environment

When working on a Label Vier starter kit WordPress project, the site is running in a Docker environment. When doing checks or running commands, use `npm run` for accessing the Docker environment.

For example, when running a `wp` cli command, run `npm run wp`. If you want to add assoc argument, add an extra -- to escape npm. I.e. `npm run wp -- --info`

Check .env file for the correct ports and urls and other settings.

## Theme structure (starterkit v7 and up)

From v7 the theme splits PHP in two layers: `inc/` for procedural glue and `modules/` for features with state or a lifecycle. Check the theme version in `style.scss` to know which layout applies; for older projects see [Legacy: inc/ with its own autoloader](#legacy-inc-with-its-own-autoloader) below.

### Where does code go?

| Code                                                   | Home                     |
|--------------------------------------------------------|--------------------------|
| State, lifecycle, collaborators, or more than one file | `modules/`               |
| Single-file, stateless, register-a-hook-and-done       | `inc/`                   |
| Markup / templates (even for a module)                 | `template-parts/`        |
| A block                                                | `template-parts/blocks/` |
| Styles or scripts (even for a module)                  | `src/scss`, `src/js`     |
| ACF field groups (even for a module)                   | `acf-json/`              |

Templates, assets and ACF stay central on purpose — the `l4` build engine, the ITCSS layering and `get_template_part()` overrides own them. A module's boundary is its **PHP logic**, nothing more. Render markup with `get_template_part( 'template-parts/...' )`.

### Dependency direction

`inc/` may call into `modules/`. `modules/` must **not** reach back into loose `inc/` functions (except genuine globals like `is_develop_environment()`). One-way only, so the two folders never melt together.

### Bootstrap

`functions.php` loads in two phases, after requiring the theme's own PSR-4 autoloader (`autoload.php`, mapping `Labelvier\` → `modules/`):

```php
// PSR-4 autoloader for the modules/ classes (Labelvier\ namespace).
require get_template_directory() . '/autoload.php';

// Phase 1: procedural glue — single-file, stateless hook-and-forget code.
foreach ( glob( get_template_directory() . '/inc/*.php' ) as $inc ) {
	require $inc;
}

// Phase 2: modules — multi-file features with state/lifecycle.
// Discovered from the modules/ folder, no manifest to maintain. Registration
// order is alphabetical, so modules must not depend on it — use hook
// priorities instead. See modules/README.md.
foreach ( labelvier_discover_modules() as $labelvier_module ) {
	( new $labelvier_module() )->register();
}
```

There is no manifest. `labelvier_discover_modules()` scans `modules/*/` one level deep and registers every instantiable class implementing `Labelvier\Module`.

### Creating a module

```bash
npm run make:module Foo
npm run make:module Gutenberg/Switcher   # when the class name differs from the folder
```

The argument is the path of the file to create, relative to `modules/` and without `.php`. `Foo` and `Foo/Foo` mean the same thing. A deeper path is rejected — helper classes are not discovered, so write those by hand.

By hand it is the same three steps: copy an existing folder, rename the class file and set `namespace Labelvier\Foo;`, then put the hooks in `register()`.

Two rules make discovery work:

- **The entry class sits at the top of its folder** (`Foo/Foo.php`, `Foo/Anything.php`). Only this level is scanned.
- **The filename matches the class name**, as PSR-4 requires.

Helper classes go in a subfolder (`Foo/Support/Thing.php`). They are skipped by discovery and stay lazily autoloaded, so they only load when actually used.

To keep a module in the tree but switched off, make its `register()` return early on a condition. Deleting the folder also works.

### The contract

Implement `Labelvier\Module` and its `register(): void` method. That is the whole contract.

```php
<?php

namespace Labelvier\Cookies;

use Labelvier\Module;

class Cookies implements Module {

	public function register(): void {
		add_action( 'wp_enqueue_scripts', [ $this, 'enqueue' ] );
		add_action( 'wp_footer', [ $this, 'render_banner' ] );
	}

	public function enqueue(): void {
		// ...
	}

	public function render_banner(): void {
		get_template_part( 'template-parts/cookies/banner' );
	}
}
```

### Layout

```
modules/
  Module.php          # interface: register()
  Cookies/
    Cookies.php       # entry class, discovered
    Support/
      Consent.php     # helper, lazily autoloaded
  Cli/
    HelloWorld.php
  Gutenberg/
    Switcher.php
  Menu/
    MonkeyMenu.php
  Performance/
    CssOptimization.php
    JsOptimization.php
  PageHeader/
    PageHeader.php
```

A module folder holds PHP classes only. Split into more classes when a feature grows, putting the extras in a subfolder as shown above.

## Legacy: inc/ with its own autoloader

Applies to starterkit versions before v7, and to plugins that still follow this pattern. In these projects the inc folder is important because we add controller / service functionality there. If the functionality gets too big you should create a subfolder with namespace and autoload.

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

In a v7+ theme this pattern is superseded by `modules/` — do not add a second autoloader inside `inc/`.
