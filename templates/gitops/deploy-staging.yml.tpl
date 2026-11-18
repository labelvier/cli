name: Deploy to staging

# GitOps: every PR merged into __BASE_BRANCH__ (a push to it) is merged into the
# staging branch, which is then deployed to staging with Deployer.
on:
  push:
    branches: [__BASE_BRANCH__]
  workflow_dispatch:

# Deploys run one at a time; a newer merge waits for the running deploy.
concurrency:
  group: deploy-staging
  cancel-in-progress: false

permissions:
  contents: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: staging
    timeout-minutes: 20
    env:
      DEPLOY_STAGING_HOSTNAME: ${{ secrets.DEPLOY_STAGING_HOSTNAME }}
      DEPLOY_STAGING_USER: ${{ secrets.DEPLOY_STAGING_USER }}
      DEPLOY_STAGING_PORT: ${{ secrets.DEPLOY_STAGING_PORT }}
      DEPLOY_STAGING_PATH: ${{ secrets.DEPLOY_STAGING_PATH }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Merge __BASE_BRANCH__ into staging
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git checkout staging
          git merge --no-ff "$GITHUB_SHA" -m "chore: merge __BASE_BRANCH__ into staging"
          git push origin staging

      - uses: shivammathur/setup-php@v2
        with:
          php-version: '__PHP_VERSION__'
          tools: composer

      #NODE#- uses: actions/setup-node@v4
      #NODE#  with:
      #NODE#    node-version: 24
      #NODE#    cache: npm

      - run: composer install --no-interaction --no-progress --prefer-dist

      - name: Configure SSH
        env:
          SSH_KEY: ${{ secrets.DEPLOY_STAGING_SSH_KEY }}
          KNOWN_HOSTS: ${{ secrets.DEPLOY_STAGING_KNOWN_HOSTS }}
        run: |
          install -m 700 -d ~/.ssh
          printf '%s\n' "$SSH_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          # The host key `labelvier gitops` stored; scanning trusts whoever answers and is only a fallback.
          if [ -n "$KNOWN_HOSTS" ]; then
            printf '%s\n' "$KNOWN_HOSTS" > ~/.ssh/known_hosts
          else
            ssh-keyscan -p "${DEPLOY_STAGING_PORT:-22}" "$DEPLOY_STAGING_HOSTNAME" >> ~/.ssh/known_hosts
          fi

      - run: vendor/bin/dep deploy staging -v
