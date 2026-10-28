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

  # Runs the command. Unlike the other commands, a bare `labelvier gitops`
  # runs the wizard instead of printing the docs. Subcommands and --help still
  # go through _dispatch.
  function main() {
    if [ $# -eq 0 ]; then
      setup
    else
      _dispatch "$filename" "$@"
    fi
  }

  # @function setup
  # @description Wizard: set up GitOps for a Laravel project on SiteGround (deploy key, server, public_html symlink, GitHub secrets, first deploy). Runs when no subcommand is given.
  function setup() {
    echo -e "${__bold}Label Vier GitOps setup${__reset}"
    echo "Push to ${__bold}develop${__reset} and GitHub puts it on ${__bold}staging${__reset} for you: no more deploying by hand."
    echo
    echo "What this wizard does:"
    echo "  · GitHub deploys to staging every time something changes on develop or staging."
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

    _step 4 "Deploy key"
    _deploy_key || return 1

    _step 5 "Server layout"
    _prepare_server || return 1
    _webroot || return 1

    _step 6 "GitHub"
    _github || return 1

    _step 7 "First deploy"
    _first_deploy
  }

  # @function scaffold
  # @description Write deploy.php and the GitHub workflow from the templates and require deployer/deployer; skips files that exist.
  function scaffold() {
    _preflight || return 1
    _scaffold_files
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
    echo -e "${__bold}${__blue}Step $1/7 · $2${__reset}"
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

  # Make a server path home-relative unless it is absolute or starts with ~.
  function _home_path() {
    local path="${1%/}"
    case "$path" in
      /* | "~"*) echo "$path" ;;
      *) echo "~/$path" ;;
    esac
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
    deploy_path=$(_home_path "$(_ask "Deploy path on the server (releases/, shared/ and current end up here)" "www/$domain/app")")
    public_path=$(_home_path "$(_ask "Web root symlink (SiteGround public_html)" "www/$domain/public_html")")
  }

  # The server's default `php` is what Deployer uses. Warn when it is older than the project needs
  # and offer to change it with `labelvier siteground site:php`.
  function _check_php() {
    local required installed
    required=$(_required_php)
    installed=$(_server_php)
    if [ -z "$installed" ]; then
      _warn "Could not read the PHP version on the server (php -v)."
      return 0
    fi
    php_version="$installed"
    if [ -z "$required" ] || _version_gte "$installed" "$required"; then
      _ok "Server PHP $installed${required:+ (project needs >= $required)}"
      return 0
    fi

    _warn "Server PHP is $installed, the project needs >= $required. Composer would fail on the server."
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
    installed=$(_server_php)
    if [ -n "$installed" ] && _version_gte "$installed" "$required"; then
      php_version="$installed"
      _ok "Server PHP is now $installed"
    else
      _warn "The server still reports PHP ${installed:-unknown}; check Site Tools → Devs → PHP Manager."
    fi
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

    # First setup of an existing rsync-style install: carry over its state.
    local moved
    moved=$(_remote "
      cd $deploy_path || exit 1
      [ -f .env ] && [ ! -f shared/.env ] && cp .env shared/.env && echo .env
      [ -d storage ] && [ ! -d shared/storage ] && cp -a storage shared/storage && echo storage
      [ -f public/.htaccess ] && [ ! -f shared/public/.htaccess ] && cp public/.htaccess shared/public/.htaccess && echo .htaccess
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
      _warn "Skipped. Set them yourself or re-run: labelvier gitops"
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
      _warn "Skipped. Commit deploy.php and the workflow, merge to $(_default_base_branch) and the action does the rest."
      return 0
    fi
    DEPLOY_STAGING_HOSTNAME="$host" DEPLOY_STAGING_USER="$user" DEPLOY_STAGING_PORT="$port" \
      DEPLOY_STAGING_PATH="$deploy_path" DEPLOY_STAGING_PUBLIC_PATH="$public_path" \
      DEPLOY_STAGING_KEY_FILE="$key_file" vendor/bin/dep deploy "$stage" -v || {
      _fail "Deploy failed. Fix the error above and run: labelvier gitops"
      return 1
    }
    echo
    _ok "Done. Commit deploy.php and .github/workflows/deploy-$stage.yml; merges to $(_default_base_branch) deploy from now on."
  }

  # Extra ssh options (the deploy key once it exists); kept as a function-wide array.
  local _ssh_extra=()

  main "$@"
)
