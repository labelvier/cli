#!/bin/bash

gitops() (

  # Local filename to echo the documentation.
  local filename="gitops.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  # Deploy key pairs, outside the project so nothing can be committed by accident.
  local state_dir="${GITOPS_STATE_DIR:-$HOME/.config/labelvier/gitops}"
  local templates_dir="$current_dir/../templates/gitops"
  # Environment name in GitHub; also the branch that is deployed.
  local stage="staging"

  # Answers collected by the wizard, shared by its steps.
  local repo="" repo_url="" host="" user="" port="" domain=""
  local deploy_path="" public_path="" php_version="" base_branch="" key_file=""

  # Runs the command.
  function main() {
    _dispatch "$filename" "$@"
  }

  # @function setup
  # @description Wizard: set up GitOps for a Laravel project on SiteGround (deploy key, server, public_html symlink, GitHub secrets, first deploy).
  function setup() {
    echo -e "${__bold}Label Vier GitOps setup${__reset}"
    echo -e "Push to ${__red}develop${__reset} and GitHub puts it on ${__red}staging${__reset} for you: no more deploying by hand."
    echo
    echo "What this wizard does:"
    echo -e "  · GitHub deploys to staging every time something changes on ${__red}develop${__reset} or ${__red}staging${__reset}."
    echo "  · Passwords and keys are set once, in the right places, so they stay safe:"
    echo "      - the deploy key goes into GitHub as an encrypted secret,"
    echo "      - the app .env stays on the server and never touches GitHub."
    echo "  · Nothing on your server or in GitHub changes without your yes."

    _step 1 "Project"
    _preflight || return 1

    _step 2 "Server"
    _pick_server || return 1
    _pick_paths || return 1
    _check_php || return 1

    _step 3 "Project files"
    _scaffold_files || return 1
    _tests || return 1

    _step 4 "Deploy key"
    _deploy_key || return 1

    _step 5 "Server layout"
    _prepare_server || return 1
    _webroot || return 1

    _step 6 "GitHub"
    _github || return 1

    _step 7 "First deploy"
    _first_deploy || return 1

    _step 8 "Activate GitOps"
    _publish
  }

  # @function tests
  # @description Check for local tests and offer to run them in GitHub Actions on every PR and before each staging deploy.
  function tests() {
    local _steps_total=2
    _step 1 "Tests"
    _preflight || return 1
    base_branch="${base_branch:-$(_default_base_branch)}"
    _tests || return 1

    # A workflow only runs once it is on the pushed branch, same as at the end of setup.
    _step 2 "Activate"
    _publish
  }

  # @function status
  # @description Show what is in place for GitOps: project files, deploy key, GitHub environment, secrets and branch.
  function status() {
    _preflight || return 1
    echo
    _check_file deploy.php
    _check_file .github/workflows/deploy-$stage.yml
    if [ -f composer.json ] && grep -q '"deployer/deployer"' composer.json; then
      _ok "deployer/deployer in composer.json"
    else
      _warn "deployer/deployer missing in composer.json"
    fi

    if [ -f "$(_key_path)" ]; then
      _ok "deploy key $(_key_path)"
    else
      _warn "no deploy key yet ($(_key_path))"
    fi

    local secrets
    secrets=$(gh secret list --env "$stage" --repo "$repo" 2>/dev/null | awk '{print $1}')
    local name
    for name in DEPLOY_STAGING_SSH_KEY DEPLOY_STAGING_HOSTNAME DEPLOY_STAGING_USER DEPLOY_STAGING_PORT DEPLOY_STAGING_PATH; do
      if echo "$secrets" | grep -qx "$name"; then
        _ok "secret $name"
      else
        _warn "secret $name missing in environment '$stage'"
      fi
    done

    if git ls-remote --exit-code --heads origin "$stage" >/dev/null 2>&1; then
      _ok "branch $stage on origin"
    else
      _warn "branch $stage missing on origin"
    fi
  }

  # ---------------------------------------------------------------- output

  function _step() {
    echo
    echo -e "${__bold}${__blue}Step $1/${_steps_total:-8} · $2${__reset}"
  }
  function _ok() { echo -e "  ${__green}✓${__reset} $1"; }
  function _warn() { echo -e "  ${__red}!${__reset} $1"; }
  function _fail() { echo -e "  ${__red}✗${__reset} $1"; }
  function _check_file() {
    if [ -f "$1" ]; then _ok "$1"; else _warn "$1 missing"; fi
  }

  # Prompt for a value, showing an optional default. Echoes the result.
  function _ask() {
    local answer
    if [ -n "$2" ]; then
      read -r -p "  $1 [$2]: " answer
      echo "${answer:-$2}"
    else
      read -r -p "  $1: " answer
      echo "$answer"
    fi
  }

  # Yes/no question; the default answer is yes unless a second argument "n" is given.
  function _yes() {
    local answer hint="[Y/n]"
    [ "$2" = "n" ] && hint="[y/N]"
    read -r -p "  $1 $hint " answer
    case "$answer" in
      [yYjJ]*) return 0 ;;
      [nN]*) return 1 ;;
    esac
    [ "$2" != "n" ]
  }

  # ---------------------------------------------------------------- remote helpers

  # Run a command on the server with your own key or, once it exists, the deploy key.
  function _remote() {
    command ssh -o BatchMode=yes -o ConnectTimeout=10 -p "$port" "${_ssh_extra[@]}" "$user@$host" "$@"
  }

  function _key_path() {
    echo "$state_dir/$(echo "${repo:-project}" | tr '/' '_')-$stage"
  }

  # ---------------------------------------------------------------- step 1

  function _preflight() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      _fail "Not inside a git repository. Run this from your project."
      return 1
    fi
    if [ ! -f composer.json ] || ! grep -q '"laravel/framework"' composer.json; then
      _fail "No Laravel project found (composer.json without laravel/framework). Only Laravel + Deployer is supported."
      return 1
    fi
    if ! command -v gh >/dev/null 2>&1; then
      _fail "GitHub CLI missing. Install it with: brew install gh"
      return 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
      _fail "GitHub CLI is not logged in. Run: gh auth login"
      return 1
    fi
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
    if [ -z "$repo" ]; then
      _fail "Could not find the GitHub repository (is origin pushed to GitHub?)."
      return 1
    fi
    repo_url="git@github.com:$repo.git"
    _ok "Repository $repo"
    _ok "GitHub CLI logged in"
  }

  # Write deploy.php and the workflow from the templates; never overwrite.
  function _scaffold_files() {
    base_branch="${base_branch:-$(_default_base_branch)}"

    if [ -f deploy.php ] && [ -f ".github/workflows/deploy-$stage.yml" ]; then
      _ok "deploy.php and the workflow already exist"
    else
      base_branch=$(_ask "Branch whose merges get deployed" "$base_branch")
      # CI runs the same PHP as the server; the wizard read it in step 2.
      php_version="${php_version:-$(_ask "PHP version for CI" "8.4")}"
      mkdir -p .github/workflows
      _render "$templates_dir/deploy.php.tpl" deploy.php
      _render "$templates_dir/deploy-staging.yml.tpl" ".github/workflows/deploy-$stage.yml"
    fi

    if grep -q '"deployer/deployer"' composer.json; then
      _ok "deployer/deployer already required"
    elif _yes "Run 'composer require --dev deployer/deployer' now?"; then
      composer require --dev deployer/deployer --no-interaction || return 1
    else
      _warn "Add deployer/deployer yourself: the workflow needs vendor/bin/dep"
    fi
  }

  # Local tests: offer to run them locally, then in GitHub Actions on PRs and before each deploy.
  function _tests() {
    local count runner cmd workflow=".github/workflows/deploy-$stage.yml"
    count=$(find tests -name '*Test.php' 2>/dev/null | wc -l | tr -d ' ')
    if [ "${count:-0}" = "0" ]; then
      _warn "No tests found in tests/. Nothing to run in CI; add some, then: labelvier gitops tests"
      return 0
    fi
    runner="PHPUnit"
    grep -q '"pestphp/pest"' composer.json && runner="Pest"
    cmd="php artisan test"
    grep -q '"test"[[:space:]]*:' composer.json && cmd="composer test"
    _ok "$count test files ($runner), run with: $cmd"

    if [ -f .github/workflows/tests.yml ] && grep -qs "workflows/tests.yml" "$workflow"; then
      _ok "Tests already run in GitHub Actions (PRs and before each deploy)"
      return 0
    fi

    if _yes "Run them locally now to check they pass?"; then
      if ! $cmd; then
        _warn "The tests fail locally. In CI they would block every staging deploy."
        _yes "Continue anyway?" n || return 1
      fi
    fi

    local gate=0 pr=0
    _yes "Run the tests in GitHub Actions before each $stage deploy (a failing test blocks the deploy)?" && gate=1
    _yes "Run the tests on every PR into ${base_branch:-$(_default_base_branch)} that is opened or updated?" && pr=1
    if [ "$gate" = 0 ] && [ "$pr" = 0 ]; then
      _warn "Skipped. Add them later with: labelvier gitops tests"
      return 0
    fi
    if ! grep -qs 'DB_CONNECTION' phpunit.xml phpunit.xml.dist; then
      _warn "phpunit.xml sets no DB_CONNECTION: CI has no database, so set sqlite there if the tests need one."
    fi

    _ci_php_version
    mkdir -p .github/workflows
    _render_tests "$cmd" "$pr"
    [ "$gate" = 1 ] && _gate_deploy "$workflow"
    return 0
  }

  # CI runs the PHP version SiteGround gives the site, not a guess from composer.json.
  function _ci_php_version() {
    [ -n "$php_version" ] && return 0
    if [ -z "$domain" ]; then
      domain=$(_ask "Domain of the staging site (to read its PHP version from SiteGround)" "")
    fi
    [ -n "$domain" ] && php_version=$(_site_php)
    if [ -n "$php_version" ]; then
      _ok "PHP $php_version, as set on SiteGround for $domain"
    else
      _warn "Could not read the PHP version from SiteGround."
      php_version=$(_ask "PHP version for CI" "$(_required_php || true)")
      php_version="${php_version:-8.4}"
    fi
  }

  # Write the tests workflow; the Node steps are only kept when package.json has a build script.
  function _render_tests() {
    local to=".github/workflows/tests.yml" node_filter="/#NODE#/d" pr_filter="/#PR#/d"
    if [ -f "$to" ]; then
      _ok "$to already exists, left alone"
      return
    fi
    grep -qs '"build"[[:space:]]*:' package.json && node_filter="s/#NODE#//"
    [ "$2" = "1" ] && pr_filter="s/#PR#//"
    sed -e "$node_filter" -e "$pr_filter" \
      -e "s#__PHP_VERSION__#$php_version#g" \
      -e "s#__BASE_BRANCH__#${base_branch:-$(_default_base_branch)}#g" \
      -e "s#__TEST_CMD__#$1#g" \
      "$templates_dir/tests.yml.tpl" >"$to"
    _ok "Wrote $to"
  }

  # Make the deploy job wait for the tests job (calls tests.yml as a reusable workflow).
  function _gate_deploy() {
    local workflow="$1" tmp
    if [ ! -f "$workflow" ]; then
      _warn "$workflow not found: the tests run on PRs, but nothing blocks a deploy yet."
      return 0
    fi
    if grep -q "workflows/tests.yml" "$workflow"; then
      _ok "$workflow already waits for the tests"
      return 0
    fi
    tmp=$(mktemp)
    awk '
      /^jobs:/ { print; print "  tests:"; print "    uses: ./.github/workflows/tests.yml"; print ""; next }
      /^  deploy:/ { print; print "    needs: tests"; next }
      { print }
    ' "$workflow" >"$tmp" && mv "$tmp" "$workflow"
    _ok "$workflow: deploy now needs the tests job"
  }

  function _default_base_branch() {
    if git show-ref --verify --quiet refs/heads/develop; then echo develop; else echo master; fi
  }

  # Copy a template to its destination with the placeholders filled in, unless it exists.
  function _render() {
    local from="$1" to="$2"
    if [ -f "$to" ]; then
      _ok "$to already exists, left alone"
      return
    fi
    sed -e "s#__APP__#$(basename "$repo")#g" \
      -e "s#__REPO_URL__#$repo_url#g" \
      -e "s#__PHP_VERSION__#$php_version#g" \
      -e "s#__BASE_BRANCH__#$base_branch#g" \
      "$from" >"$to"
    _ok "Wrote $to"
  }

  # ---------------------------------------------------------------- step 2

  # Ask for the staging domain, let SiteGround tell where it lives and prove your own SSH key gets in.
  function _pick_server() {
    domain=$(_ask "Domain of the staging site (as in SiteGround)" "")
    if [ -z "$domain" ]; then
      _fail "No domain given."
      return 1
    fi

    local sg="${GITOPS_SITEGROUND:-siteground}" target
    target=$($sg site:ssh "$domain" 2>/dev/null | sed -n 's/^ssh -p \([0-9]*\) \([^@ ]*\)@\([^ ]*\)$/\1 \2 \3/p' | head -n 1)
    if [ -z "$target" ]; then
      _fail "SiteGround does not know '$domain' (or you are not logged in). Check: labelvier siteground login, labelvier siteground accounts"
      return 1
    fi
    port=$(echo "$target" | cut -d' ' -f1)
    user=$(echo "$target" | cut -d' ' -f2)
    host=$(echo "$target" | cut -d' ' -f3)
    _ok "$domain found in SiteGround: $user@$host:$port"

    _ssh_extra=()
    if _remote true 2>/dev/null; then
      _ok "Your own SSH key can log in"
      return 0
    fi

    _warn "Your own SSH key cannot log in yet."
    if ! _yes "Authorize your default public key on $domain with 'labelvier siteground site:ssh-key' now?"; then
      _fail "Without a login the wizard cannot prepare the server."
      return 1
    fi
    $sg site:ssh-key "$domain" || {
      _fail "Authorizing the key failed."
      return 1
    }
    if _remote true 2>/dev/null; then
      _ok "Your own SSH key can log in"
    else
      _fail "Still cannot log in as $user@$host:$port. SiteGround can take a minute to apply a new key; try again."
      return 1
    fi
  }

  function _pick_paths() {
    # SiteGround fixes the layout: www/<domain>/public_html is the web root, so releases live next to it.
    deploy_path="~/www/$domain"
    public_path="$deploy_path/public_html"
    _ok "Deploy path $deploy_path, web root $public_path"
  }

  # Deployer uses the server's default `php`, the site itself runs the version set in SiteGround. CI follows the
  # site. Warn when either is older than the project needs and offer to change it with `labelvier siteground site:php`.
  function _check_php() {
    local required cli site
    required=$(_required_php)
    cli=$(_server_php)
    site=$(_site_php)
    php_version="${site:-$cli}"
    if [ -z "$php_version" ]; then
      _warn "Could not read the PHP version from SiteGround or the server (php -v)."
      return 0
    fi
    [ -n "$site" ] && _ok "SiteGround PHP for $domain: $site"
    [ -n "$cli" ] && _ok "Server php (cli, used by Deployer): $cli"

    if [ -z "$required" ] || { { [ -z "$site" ] || _version_gte "$site" "$required"; } && { [ -z "$cli" ] || _version_gte "$cli" "$required"; }; }; then
      [ -n "$required" ] && _ok "Both are at least $required, what the project needs"
      return 0
    fi

    _warn "PHP is older than the $required the project needs. Composer would fail on the server."
    if ! _yes "Change the PHP version of $domain with 'labelvier siteground site:php' now?"; then
      _warn "Left as is. Fix it in Site Tools → Devs → PHP Manager before the first deploy."
      return 0
    fi
    local wanted
    wanted=$(_ask "PHP version to set" "$required")
    # GITOPS_SITEGROUND swaps in another command (the tests stub it, a function would win over a stub on PATH).
    ${GITOPS_SITEGROUND:-siteground} site:php "$domain" --php "$wanted" || {
      _fail "Changing the PHP version failed."
      return 1
    }
    cli=$(_server_php)
    site=$(_site_php)
    php_version="${site:-$cli}"
    if { [ -z "$site" ] || _version_gte "$site" "$required"; } && { [ -z "$cli" ] || _version_gte "$cli" "$required"; }; then
      _ok "PHP is now ${php_version}"
    else
      _warn "SiteGround reports ${site:-unknown}, the server ${cli:-unknown}; check Site Tools → Devs → PHP Manager."
    fi
  }

  # Major.minor of the PHP version SiteGround runs for the site (`siteground site:info`), empty when "managed" or unknown.
  function _site_php() {
    ${GITOPS_SITEGROUND:-siteground} site:info "$domain" 2>/dev/null | sed -n 's/^[[:space:]]*PHP[[:space:]]*PHP \([0-9]*\.[0-9]*\).*/\1/p' | head -n 1
  }

  # Major.minor of the default php on the server, empty when it cannot be read.
  function _server_php() {
    _remote "php -v" 2>/dev/null | head -n 1 | sed -n 's/^PHP \([0-9]*\.[0-9]*\).*/\1/p'
  }

  # Lowest major.minor that composer.json's "require.php" allows, empty when not set.
  function _required_php() {
    sed -n 's/.*"php"[[:space:]]*:[[:space:]]*"[^0-9]*\([0-9]*\.[0-9]*\).*/\1/p' composer.json | head -n 1
  }

  # Succeeds when major.minor $1 is at least $2.
  function _version_gte() {
    awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, "."); split(b, y, "."); exit !((x[1] * 1000 + x[2]) >= (y[1] * 1000 + y[2])) }'
  }

  # ---------------------------------------------------------------- step 4

  function _deploy_key() {
    key_file=$(_key_path)
    mkdir -p "$state_dir" && chmod 700 "$state_dir"

    if [ -f "$key_file" ]; then
      _ok "Using existing deploy key $key_file"
    else
      ssh-keygen -q -t ed25519 -N "" -C "gitops-$stage-$(basename "$repo")" -f "$key_file" || return 1
      _ok "Created $key_file"
    fi

    local pub
    pub=$(cat "$key_file.pub")
    if _remote "grep -qF '$pub' ~/.ssh/authorized_keys 2>/dev/null"; then
      _ok "Public key already authorized on the server"
    else
      if ! _yes "Authorize the public key on the server (~/.ssh/authorized_keys)?"; then
        _fail "The deploy key has to be authorized to continue."
        return 1
      fi
      _remote "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" || return 1
      _ok "Key authorized"
    fi

    # From here on every remote command proves the deploy key itself works.
    _ssh_extra=(-i "$key_file" -o IdentitiesOnly=yes)
    if _remote true; then
      _ok "Logging in with the deploy key works"
    else
      _fail "Login with the deploy key failed. Check SiteGround Site Tools → Devs → SSH Keys Manager."
      return 1
    fi
  }

  # ---------------------------------------------------------------- step 5

  # shared/ holds what must survive releases: .env, storage and the host's .htaccess.
  function _prepare_server() {
    _remote "mkdir -p $deploy_path/shared/public" || return 1

    # First setup of an existing rsync-style install (state in the deploy path or in an app/ folder): carry it over.
    local moved
    moved=$(_remote "
      cd $deploy_path || exit 1
      for old in . app; do
        [ -f \$old/.env ] && [ ! -f shared/.env ] && cp \$old/.env shared/.env && echo .env
        [ -d \$old/storage ] && [ ! -d shared/storage ] && cp -a \$old/storage shared/storage && echo storage
        [ -f \$old/public/.htaccess ] && [ ! -f shared/public/.htaccess ] && cp \$old/public/.htaccess shared/public/.htaccess && echo .htaccess
      done
      true")
    [ -n "$moved" ] && _ok "Copied into shared/: $(echo "$moved" | tr '\n' ' ')"

    if _remote "test -f $deploy_path/shared/.env"; then
      _ok "shared/.env exists on the server"
    else
      _warn "No .env on the server yet. It is never taken from GitHub."
      local env_file
      env_file=$(_ask "Local env file to upload once (empty = I will do it myself)" "")
      if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        command scp -q -o BatchMode=yes -P "$port" "${_ssh_extra[@]}" "$env_file" "$user@$host:$deploy_path/shared/.env" && _ok "Uploaded $env_file to shared/.env"
      else
        _warn "Create $deploy_path/shared/.env on the server before the first deploy."
      fi
    fi

    if ! _remote "test -f $deploy_path/shared/public/.htaccess"; then
      _warn "No shared/public/.htaccess: the release will use the repo one without SiteGround's PHP handler line."
    fi
  }

  # public_html must be a symlink to current/public; an existing directory is moved aside or removed.
  function _webroot() {
    local state
    state=$(_remote "if [ -L $public_path ]; then echo link; elif [ -d $public_path ]; then echo dir; else echo none; fi")
    case "$state" in
      link)
        _ok "$public_path is already a symlink ($(_remote "readlink $public_path"))"
        ;;
      none)
        _ok "$public_path does not exist; deploy creates the symlink"
        ;;
      dir)
        echo "  $public_path is a real directory. The deploy needs a symlink there."
        echo "    1) Move it aside (public_html.bak-<date>), recommended"
        echo "    2) Delete it"
        echo "    3) Leave it, I will do it myself"
        local choice backup
        choice=$(_ask "Choice" "1")
        case "$choice" in
          1)
            backup="$public_path.bak-$(date +%Y%m%d)"
            _remote "mv $public_path $backup" || return 1
            _ok "Moved to $backup. The site is offline until the first deploy has run."
            ;;
          2)
            local typed
            typed=$(_ask "This cannot be undone. Type the domain ($domain) to confirm" "")
            if [ "$typed" != "$domain" ]; then
              _fail "Not confirmed, nothing deleted."
              return 1
            fi
            _remote "rm -rf $public_path" || return 1
            _ok "Deleted $public_path. The site is offline until the first deploy has run."
            ;;
          *)
            _warn "Left as is. The first deploy fails at 'deploy:public_html' until it is a symlink."
            ;;
        esac
        ;;
    esac
  }

  # ---------------------------------------------------------------- step 6

  function _github() {
    echo "  Environment '$stage' in $repo gets these secrets (names only, values never printed):"
    echo "    DEPLOY_STAGING_SSH_KEY, _HOSTNAME, _USER, _PORT, _PATH"
    if ! _yes "Create the environment and set the secrets?"; then
      _warn "Skipped. Set them yourself or re-run: labelvier gitops setup"
      return 0
    fi

    gh api --method PUT "repos/$repo/environments/$stage" >/dev/null || {
      _fail "Could not create the environment (needs admin rights on the repo)."
      return 1
    }
    _ok "Environment '$stage'"

    gh secret set DEPLOY_STAGING_SSH_KEY --env "$stage" --repo "$repo" <"$key_file" >/dev/null || return 1
    gh secret set DEPLOY_STAGING_HOSTNAME --env "$stage" --repo "$repo" --body "$host" >/dev/null || return 1
    gh secret set DEPLOY_STAGING_USER --env "$stage" --repo "$repo" --body "$user" >/dev/null || return 1
    gh secret set DEPLOY_STAGING_PORT --env "$stage" --repo "$repo" --body "$port" >/dev/null || return 1
    gh secret set DEPLOY_STAGING_PATH --env "$stage" --repo "$repo" --body "$deploy_path" >/dev/null || return 1
    _ok "5 secrets set"

    if git ls-remote --exit-code --heads origin "$stage" >/dev/null 2>&1; then
      _ok "Branch $stage exists on origin"
    elif _yes "Branch '$stage' does not exist on origin. Create it from ${base_branch:-$(_default_base_branch)}?"; then
      git push origin "refs/heads/${base_branch:-$(_default_base_branch)}:refs/heads/$stage" && _ok "Pushed $stage"
    else
      _warn "The workflow checks out '$stage'; create it before the first merge."
    fi
  }

  # ---------------------------------------------------------------- step 7

  # A workflow_dispatch only works once the workflow is on the default branch, so deploy from here once.
  function _first_deploy() {
    if [ ! -x vendor/bin/dep ]; then
      _warn "vendor/bin/dep not found. Run composer install, then: vendor/bin/dep deploy $stage"
      return 0
    fi
    echo "  The first deploy runs from this machine with the deploy key; later deploys run in GitHub Actions."
    if ! _yes "Deploy $(git rev-parse --abbrev-ref HEAD) to $stage now?"; then
      _warn "Skipped the first deploy; the action does it after the next push to $(_default_base_branch)."
      return 0
    fi
    DEPLOY_STAGING_HOSTNAME="$host" DEPLOY_STAGING_USER="$user" DEPLOY_STAGING_PORT="$port" \
      DEPLOY_STAGING_PATH="$deploy_path" DEPLOY_STAGING_PUBLIC_PATH="$public_path" \
      DEPLOY_STAGING_KEY_FILE="$key_file" vendor/bin/dep deploy "$stage" -v || {
      _fail "Deploy failed. Fix the error above and run: labelvier gitops setup"
      return 1
    }
    echo
    _ok "Deployed."
  }

  # GitHub Actions only runs a workflow that is on the pushed branch, so without this push nothing deploys.
  function _publish() {
    local base="${base_branch:-$(_default_base_branch)}" current files changed
    current=$(git rev-parse --abbrev-ref HEAD)
    local f
    files=""
    for f in deploy.php ".github/workflows/deploy-$stage.yml" .github/workflows/tests.yml composer.json composer.lock; do
      [ -e "$f" ] && files="$files $f"
    done
    changed=$(git status --porcelain -- $files 2>/dev/null)

    if [ -z "$changed" ]; then
      _ok "deploy.php and the workflow are already committed"
    else
      echo "$changed" | sed 's/^/    /'
      if ! _yes "Commit these files on '$current'?"; then
        _warn "Not committed: no deploy runs until deploy.php and the workflow are on $base."
        return 0
      fi
      git add -- $files || return 1
      git commit -q -m "ci: deploy $stage with Deployer via GitHub Actions" -- $files || return 1
      _ok "Committed on $current"
    fi

    if [ "$current" = "$base" ]; then
      _yes "Push $base to origin now? Every merge here then deploys to $stage." || {
        _warn "Not pushed. Push $base yourself to activate GitOps."
        return 0
      }
      git push origin "$base" || return 1
    else
      _yes "Push '$current' to origin/$base now (fast-forward only)? Every merge there then deploys to $stage." || {
        _warn "Not pushed. Merge '$current' into $base to activate GitOps."
        return 0
      }
      git push origin "refs/heads/$current:refs/heads/$base" || {
        _warn "Push to $base was rejected. Open a PR from '$current' into $base instead."
        return 0
      }
    fi
    _ok "Pushed to $base. GitHub Actions deploys from now on: gh run watch"
  }

  # Extra ssh options (the deploy key once it exists); kept as a function-wide array.
  local _ssh_extra=()

  main "$@"
)
