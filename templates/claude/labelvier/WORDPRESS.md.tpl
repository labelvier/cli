# WordPress development

The inc folder is important because we add controller / service functionality there. If the functionality gets to big you should create a subfolder with namespace and autoload.

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

When working on a Label Vier starter kit WordPress project, the site is running in a Docker environment. When doing checks or running commands, use `npm run` for accessing the docker environment.

For example, when running a `wp` cli command, run `npm run wp`. If you want to add assoc argument, add an extra -- to escape npm. I.e. `npm run wp -- --info`

Check .env file for the correct ports and urls and other settings.
