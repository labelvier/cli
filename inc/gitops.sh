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
  local repo="" repo_url="" ssh_alias="" host="" user="" port="" domain=""
  local deploy_path="" public_path="" php_bin="" php_version="" base_branch="" key_file=""

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
    echo "Every merged PR on the base branch gets merged into '$stage' and deployed with Deployer."
    echo "Nothing on the server or in GitHub changes without your yes. The app .env stays on the server and is never sent to GitHub."

    _step 1 "Project"
    _preflight || return 1
    _scaffold_files || return 1

    _step 2 "Server"
    _pick_server || return 1
    _pick_paths || return 1

    _step 3 "Deploy key"
    _deploy_key || return 1

    _step 4 "Server layout"
    _prepare_server || return 1
    _webroot || return 1

    _step 5 "GitHub"
    _github || return 1

    _step 6 "First deploy"
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
    echo -e "${__bold}${__blue}Step $1/6 · $2${__reset}"
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

  # Run a command on the server through the chosen SSH alias or, once known, the deploy key.
  function _remote() {
    command ssh -o BatchMode=yes -o ConnectTimeout=10 "${_ssh_extra[@]}" "$ssh_alias" "$@"
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
    local app php_default
    app=$(basename "$repo")
    base_branch="${base_branch:-$(_default_base_branch)}"
    php_default="${php_version:-8.4}"

    if [ -f deploy.php ] && [ -f ".github/workflows/deploy-$stage.yml" ]; then
      _ok "deploy.php and the workflow already exist"
    else
      base_branch=$(_ask "Branch whose merges get deployed" "$base_branch")
      php_version=$(_ask "PHP version on the server (and in CI)" "$php_default")
      php_bin="/usr/local/bin/php$(echo "$php_version" | tr -d '.')"
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
      -e "s#__PHP_BIN__#$php_bin#g" \
      -e "s#__PHP_VERSION__#$php_version#g" \
      -e "s#__BASE_BRANCH__#$base_branch#g" \
      "$from" >"$to"
    _ok "Wrote $to"
  }

  # ---------------------------------------------------------------- step 2

  function _pick_server() {
    local hosts
    hosts=$(awk '$1 == "Host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?]/) print $i }' "$HOME/.ssh/config" 2>/dev/null)
    if [ -n "$hosts" ]; then
      echo "  SSH aliases in ~/.ssh/config:"
      echo "$hosts" | sed 's/^/    · /'
    else
      echo "  No SSH aliases found. Add one with: labelvier ssh alias"
    fi
    ssh_alias=$(_ask "SSH alias of the SiteGround account" "")
    if [ -z "$ssh_alias" ]; then
      _fail "No alias given."
      return 1
    fi

    local resolved
    resolved=$(command ssh -G "$ssh_alias" 2>/dev/null)
    host=$(echo "$resolved" | awk '$1 == "hostname" {print $2}')
    user=$(echo "$resolved" | awk '$1 == "user" {print $2}')
    port=$(echo "$resolved" | awk '$1 == "port" {print $2}')

    _ssh_extra=()
    if ! _remote true 2>/dev/null; then
      _fail "Cannot log in as '$ssh_alias' ($user@$host:$port). Check the alias and your SSH key."
      return 1
    fi
    _ok "Logged in as $user@$host:$port"
  }

  function _pick_paths() {
    domain=$(_ask "Domain of the site" "")
    if [ -z "$domain" ]; then
      _fail "No domain given."
      return 1
    fi
    deploy_path=$(_home_path "$(_ask "Deploy path on the server (releases/, shared/ and current end up here)" "www/$domain/app")")
    public_path=$(_home_path "$(_ask "Web root symlink (SiteGround public_html)" "www/$domain/public_html")")

    local php_check="${php_bin:-/usr/local/bin/php$(echo "${php_version:-8.4}" | tr -d '.')}"
    if _remote "test -x $php_check"; then
      _ok "$php_check exists on the server"
    else
      _warn "$php_check not found on the server; set 'bin/php' in deploy.php to the right binary"
    fi
  }

  # ---------------------------------------------------------------- step 3

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

  # ---------------------------------------------------------------- step 4

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
        command scp -q -o BatchMode=yes "${_ssh_extra[@]}" "$env_file" "$ssh_alias:$deploy_path/shared/.env" && _ok "Uploaded $env_file to shared/.env"
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

  # ---------------------------------------------------------------- step 5

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

  # ---------------------------------------------------------------- step 6

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
