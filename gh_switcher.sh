unalias gh_original 2>/dev/null

gh_original() {
  command gh "$@"
}

export GITHUB_ENV_FILE=.github.env

gh_env_create(){
  # Fallback chain: 1st argument ($1) -> $GITHUB_ENV_FILE -> literal '.github.env'
  local file_path="${1:-${GITHUB_ENV_FILE:-.github.env}}"
  local account_input="$2"
  local email_input="$3"
  local name_input=""

  # If account input is not provided as an argument, prompt for it
  if [[ -z "$account_input" ]]; then
    echo "Please provide GitHub account name:"
    read -r account_input
  fi
  account_input="${account_input//[[:space:]]/}"

  # Resolve profile details from the public API for the entered account
  local user_info name_resolved email_resolved user_id user_login
  user_info=$(gh_original api "users/$account_input" --jq '"\(.name // .login)|\(.email // "")|\(.id)|\(.login)"' 2>/dev/null)
  if [[ -n "$user_info" ]]; then
    IFS='|' read -r name_resolved email_resolved user_id user_login <<< "$user_info"
  fi

  # If email is not passed as an argument, check resolved value or prompt
  if [[ -z "$email_input" ]]; then
    email_input="$email_resolved"
    if [[ -z "$email_input" ]]; then
      echo "No public email found for account $account_input."
      echo "Please provide email for $account_input (optional, press Enter to auto-resolve):"
      read -r email_input
      email_input="${email_input//[[:space:]]/}"
      
      # Fallback to noreply if empty
      if [[ -z "$email_input" && -n "$user_id" && -n "$user_login" ]]; then
        email_input="${user_id}+${user_login}@users.noreply.github.com"
      fi
    fi
  fi
  email_input="${email_input//[[:space:]]/}"

  # Set name
  name_input="$name_resolved"
  if [[ -z "$name_input" ]]; then
    name_input="$account_input"
  fi

  # Write all cached variables to the env file
  echo "ENV_GITHUB_ACCOUNT=$account_input" > "$file_path"
  echo "ENV_GITHUB_NAME=\"$name_input\"" >> "$file_path"
  if [[ -n "$email_input" ]]; then
    echo "ENV_GITHUB_EMAIL=\"$email_input\"" >> "$file_path"
  fi
}

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

  # Configure local git author if inside a Git repository
  gh_configure_git_author "$ENV_GITHUB_NAME" "$ENV_GITHUB_EMAIL"

  # Run the original gh command with passed arguments
  gh_original "$@"
}
