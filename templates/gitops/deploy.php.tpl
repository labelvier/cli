<?php

/**
 * Deployer config for __APP__ (Laravel) — deploys to SiteGround staging.
 *
 * Usage:
 *   vendor/bin/dep deploy staging
 *
 * The working directory is built and uploaded (no git clone on the server), so what
 * is checked out is what ships. The target comes from DEPLOY_STAGING_* in the
 * environment or, locally, from .env. See DEPLOY.md, "Staging".
 *
 * The app .env lives on the server (shared/.env) and is never uploaded: CI only
 * holds the SSH key and the target, no app secrets.
 */

namespace Deployer;

require 'recipe/laravel.php';

/** Read a DEPLOY_* setting from the environment, falling back to the local .env. */
$setting = static function (string $key): string {
    $value = getenv($key);
    if ($value !== false && $value !== '') {
        return $value;
    }

    $env = __DIR__ . '/.env';
    if (! file_exists($env)) {
        return '';
    }
    foreach (file($env, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with($line, $key . '=')) {
            return trim(substr($line, strlen($key) + 1), " \t\"'");
        }
    }

    return '';
};

/** Make a server path home-relative unless it is absolute or starts with ~. */
$remotePath = static function (string $path): string {
    $path = rtrim($path, '/');

    return ($path === '' || $path[0] === '/' || $path[0] === '~') ? $path : '~/' . $path;
};

set('application', '__APP__');
set('repository', '__REPO_URL__'); // unused: code is uploaded
set('keep_releases', 5);

// SiteGround shared hosting: the SSH user owns the files, there is no separate web user.
set('writable_mode', 'chmod');

// Pin the PHP version of the host (Site Tools -> PHP Manager); the default `php` may differ.
set('bin/php', '__PHP_BIN__');

// `/usr/local/bin/composer` is a bash wrapper on SiteGround; run the phar with the pinned PHP.
set('bin/composer', '{{bin/php}} -d memory_limit=-1 /usr/local/bin/composer.phar');

// public/.htaccess carries the host's PHP handler line, so it lives on the server.
add('shared_files', ['public/.htaccess']);

host('staging')
    ->setHostname($setting('DEPLOY_STAGING_HOSTNAME'))
    ->setRemoteUser($setting('DEPLOY_STAGING_USER'))
    ->setPort($setting('DEPLOY_STAGING_PORT') ?: 22)
    ->setDeployPath($remotePath($setting('DEPLOY_STAGING_PATH')))
    // Web root: a symlink next to the deploy path, pointing at current/public.
    ->set('public_html_path', $remotePath($setting('DEPLOY_STAGING_PUBLIC_PATH') ?: dirname($setting('DEPLOY_STAGING_PATH')) . '/public_html'))
    ->set('ssh_multiplexing', true);

// Optional key file (`labelvier gitops` uses it for the first local deploy); CI uses ~/.ssh/id_ed25519.
if ($key = $setting('DEPLOY_STAGING_KEY_FILE')) {
    host('staging')->setIdentityFile($key);
}

// Build the Vite assets locally: shared hosting can't run node.
task('deploy:assets', function () {
    runLocally('npm ci --no-audit --no-fund && npm run build');
})->desc('Build Vite assets locally');

// Upload the working directory instead of cloning on the server (no GitHub access needed there).
task('deploy:update_code', function () {
    upload(__DIR__ . '/', '{{release_path}}/', [
        'options' => [
            '--include=/public/build/***',
            '--exclude=/.git/',
            '--exclude=/.github/',
            '--exclude=/.claude/',
            '--exclude=/.env',
            '--exclude=/vendor/',
            '--exclude=/node_modules/',
            '--exclude=/storage/',
            '--exclude=/tests/',
            '--exclude=/reference/',
            '--exclude=/docs/',
            '--exclude=/bootstrap/cache/*.php',
            '--exclude=/database/*.sqlite',
            '--exclude=/public/.htaccess',
            '--filter=:- .gitignore',
        ],
    ]);
})->desc('Upload the working directory to the release');

// Point the web root at the current release. A real directory is never replaced: move it aside once.
task('deploy:public_html', function () {
    $public = get('public_html_path');
    run("if [ -e $public ] && [ ! -L $public ]; then "
        . "echo 'ERROR: $public is a real directory. Move it aside once, then redeploy.'; exit 1; fi");
    run("ln -sfn {{deploy_path}}/current/public $public");
})->desc('Symlink public_html to the current release public/');

before('deploy:update_code', 'deploy:assets');
after('deploy:symlink', 'deploy:public_html');
after('deploy:publish', 'artisan:queue:restart');
after('deploy:failed', 'deploy:unlock');
