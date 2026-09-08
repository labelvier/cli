# Global instructions

## Commit
Commit using conventional commits

## Release
Use `wp-takeoff release` to start and finish releases
```
Available functions:
  start <optional-version> - Creates a new release branch, tries to check if there is any package.json file and updates the version. Possible flags are --minor and --major. Standard version is patch. If no version is given, we'll check if there is a WordPress theme in the .env file and try to get the version from the style.scss file. If that fails, we'll check if there is a package.json file and try to get the version from there. If that fails, we'll exit.
  cancel - Cancels the release.
  abort - Alias for cancel, matching the common git merge --abort habit.
  finish - Merges the release branch into master and develop, and tags the release.
  merge-features - Checks if there are open feature branches and asks to merge them to develop.
```

## Changelog
When finishing a release create or update the CHANGELOG.md, using the keepachangelog.com principle.

## Staging
When asking 'deploy to staging' or 'zet op staging' or 'test op staging', use `wp-takeoff deploy staging`. Don't run `npm run deploy-staging` directly. If you have merge conflicts during staging deploy, fix and push the `staging` branch. After that run `wp-takeoff deploy staging` again.

## Other

@labelvier/WORDPRESS.md

@labelvier/ANGULAR.md
