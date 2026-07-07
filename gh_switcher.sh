unalias gh_original 2>/dev/null

gh_original() {
  command gh "$@"
}

export GITHUB_ENV_FILE=.github.env

gh_resolve_env_file() {
  local dir="$PWD"
  while [[ -n "$dir" ]]; do
    if [[ -f "$dir/$GITHUB_ENV_FILE" ]]; then
      echo "$dir/$GITHUB_ENV_FILE"
      return 0
    fi
    # Stop searching if we reach a git repository boundary or filesystem root
    if [[ -e "$dir/.git" || "$dir" == "/" ]]; then
      break
    fi
    dir=$(dirname "$dir")
  done
  echo "./$GITHUB_ENV_FILE"
}

gh_configure_git_author() {
  local name="$1"
  local email="$2"

  if [[ -n "$email" ]] && git rev-parse --is-inside-work-tree &>/dev/null; then
    if [[ "$(git config --local user.email 2>/dev/null)" != "$email" ]]; then
      git config --local user.name "$name"
      git config --local user.email "$email"
      echo "Configured local git author: $name <$email>"
    fi
  fi
}

gh_cache_profile_info() {
  local env_file="$1"
  local target_account="$2"
  local user_info name_resolved email_resolved

  # Query public profile details for the entered account
  user_info=$(gh_original api "users/$target_account" --jq '"\(.name // .login)|\(.email // "")"' 2>/dev/null)
  if [[ -n "$user_info" ]]; then
    name_resolved="${user_info%%|*}"
    email_resolved="${user_info##*|}"
    
    ENV_GITHUB_NAME="$name_resolved"
    ENV_GITHUB_EMAIL="$email_resolved"

    # Save to the env file
    echo "ENV_GITHUB_ACCOUNT=$target_account" > "$env_file"
    echo "ENV_GITHUB_NAME=\"$ENV_GITHUB_NAME\"" >> "$env_file"
    if [[ -n "$ENV_GITHUB_EMAIL" ]]; then
      echo "ENV_GITHUB_EMAIL=\"$ENV_GITHUB_EMAIL\"" >> "$env_file"
    fi
  fi
}

gh_env_create(){
  # Optionally accepts file path
  local file_path="${1:-${GITHUB_ENV_FILE:-.github.env}}"

  # 1. Ask for account and set it
  echo "Please provide GitHub account name:"
  read -r ENV_GITHUB_ACCOUNT
  ENV_GITHUB_ACCOUNT="${ENV_GITHUB_ACCOUNT//[[:space:]]/}"
  echo "ENV_GITHUB_ACCOUNT=$ENV_GITHUB_ACCOUNT" > "$file_path"

  # 2. Run gh_cache_profile_info
  gh_cache_profile_info "$file_path" "$ENV_GITHUB_ACCOUNT"

  # 3. Source github env
  source "$file_path"

  # 4. If email is missing, ask user for email
  if [[ -z "$ENV_GITHUB_EMAIL" ]]; then
    echo "No public email found for account $ENV_GITHUB_ACCOUNT."
    echo "Please provide email for $ENV_GITHUB_ACCOUNT (optional, press Enter to skip):"
    read -r ENV_GITHUB_EMAIL
    ENV_GITHUB_EMAIL="${ENV_GITHUB_EMAIL//[[:space:]]/}"

    # Rewrite the file to save the updated email
    echo "ENV_GITHUB_ACCOUNT=$ENV_GITHUB_ACCOUNT" > "$file_path"
    echo "ENV_GITHUB_NAME=\"$ENV_GITHUB_NAME\"" >> "$file_path"
    if [[ -n "$ENV_GITHUB_EMAIL" ]]; then
      echo "ENV_GITHUB_EMAIL=\"$ENV_GITHUB_EMAIL\"" >> "$file_path"
    fi
  fi

  # Load the finalized configurations
  source "$file_path"

  # 5. Run configure git author only if email is not empty
  if [[ -n "$ENV_GITHUB_EMAIL" ]]; then
    gh_configure_git_author "$ENV_GITHUB_NAME" "$ENV_GITHUB_EMAIL"
  fi
}

gh_ensure_active_account() {
  local target_account="$1"
  local -A seen_accounts
  local current_account

  while true; do
    # Get current active account using the underlying binary
    current_account=$(gh_original auth status --active --json hosts --jq '.hosts | add [0] .login' 2>/dev/null)

    # Normalize empty or null account names to avoid "bad array subscript" errors
    if [[ -z "$current_account" || "$current_account" == "null" ]]; then
        current_account="empty_or_null"
    fi

    # Check if satisfied
    if [[ "$current_account" == "$target_account" ]]; then
        echo "$target_account logged in"
        return 0
    fi

    # Check if we have reached this account twice (infinite loop check)
    if [[ -n "${seen_accounts[$current_account]}" ]]; then
        echo "Account '$target_account' was not found." >&2
        echo "Try: gh auth login to login with $target_account" >&2
        return 1
    fi

    # Mark as seen
    seen_accounts["$current_account"]=1

    # Switch and try again
    gh_original auth switch
  done
}

gh(){
  local env_file
  env_file=$(gh_resolve_env_file)

  if [[ -f "$env_file" ]]; then
        source "$env_file"
  else
        echo ".github.env not found"
        gh_env_create "$env_file"
        source "$env_file"
  fi

  # Trim leading/trailing whitespace from loaded variables to prevent parsing issues
  ENV_GITHUB_ACCOUNT="${ENV_GITHUB_ACCOUNT//[[:space:]]/}"
  ENV_GITHUB_NAME="${ENV_GITHUB_NAME#"${ENV_GITHUB_NAME%%[![:space:]]*}"}"
  ENV_GITHUB_NAME="${ENV_GITHUB_NAME%"${ENV_GITHUB_NAME##*[![:space:]]}"}"
  ENV_GITHUB_EMAIL="${ENV_GITHUB_EMAIL//[[:space:]]/}"

  if [[ -z $ENV_GITHUB_ACCOUNT ]]; then
        echo ".github.env does not include ENV_GITHUB_ACCOUNT. Please provide account" "$env_file"
        return 1
  fi

  # Switch active account if needed
  if ! gh_ensure_active_account "$ENV_GITHUB_ACCOUNT"; then
    return 1
  fi

  # Configure local git author if inside a Git repository and email is not empty
  if [[ -n "$ENV_GITHUB_EMAIL" ]]; then
    gh_configure_git_author "$ENV_GITHUB_NAME" "$ENV_GITHUB_EMAIL"
  fi

  # Run the original gh command with passed arguments
  gh_original "$@"
}
