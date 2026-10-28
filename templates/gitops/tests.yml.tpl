name: Tests

# Runs on every PR into __BASE_BRANCH__ that is opened or updated, and as a reusable workflow before each staging deploy.
on:
  #PR#pull_request:
  #PR#  branches: [__BASE_BRANCH__]
  workflow_call:

permissions:
  contents: read

jobs:
  tests:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4

      - uses: shivammathur/setup-php@v2
        with:
          php-version: '__PHP_VERSION__'
          tools: composer

      #NODE#- uses: actions/setup-node@v4
      #NODE#  with:
      #NODE#    node-version: 24
      #NODE#    cache: npm

      # The views need the Vite manifest.
      #NODE#- run: npm ci && npm run build

      - run: cp .env.example .env

      - run: composer install --no-interaction --no-progress --prefer-dist

      - run: php artisan key:generate

      - run: __TEST_CMD__
