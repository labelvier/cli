/**
 * Module resolve hook (node:module register) that makes `import('playwright')` fail as if the
 * optional dependency were not installed. Used by test/login.test.js; nothing is uninstalled.
 */
export async function resolve(specifier, context, next) {
	if (specifier === 'playwright') {
		const err = new Error(`Cannot find package 'playwright' (hidden by test/fixtures/no-playwright-hook.mjs)`);
		err.code = 'ERR_MODULE_NOT_FOUND';
		throw err;
	}
	return next(specifier, context);
}
