alias gh_original='command gh'

# Fallback function for non-interactive shells where aliases are not expanded
gh_original() {
  command gh "$@"
}

export GITHUB_ENV_FILE=.github.env

gh_env_create(){
  echo "$1" && read
  echo "ENV_GITHUB_ACCOUNT=$REPLY" > "$2"
}

gh(){
  local env_file=""
  local dir="$PWD"

  # Search upwards for the config file
  while [[ -n "$dir" ]]; do
    if [[ -f "$dir/$GITHUB_ENV_FILE" ]]; then
      env_file="$dir/$GITHUB_ENV_FILE"
      break
    fi
    # Stop searching if we reach a git repository boundary
    if [[ -e "$dir/.git" ]]; then
      break
    fi
    if [[ "$dir" == "/" ]]; then
      break
    fi
    dir=$(dirname "$dir")
  done

  # Fallback to current directory if not found
  if [[ -z "$env_file" ]]; then
    env_file="./$GITHUB_ENV_FILE"
  fi

  if [[ -f "$env_file" ]]; then
        source "$env_file"
  else
        echo ".github.env not found"
        gh_env_create ".github.env not found. Please provide account" "$env_file"
        source "$env_file"
  fi

  if [[ -z $ENV_GITHUB_ACCOUNT ]]; then
        echo ".github.env does not include ENV_GITHUB_ACCOUNT. Please provide account" "$env_file"
  fi

  # Keep track of active GitHub accounts we encounter to prevent infinite loops
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
    if [[ "$current_account" == "$ENV_GITHUB_ACCOUNT" ]]; then
        echo "$ENV_GITHUB_ACCOUNT logged in"
        break
    fi

    # Check if we have reached this account twice
    if [[ -n "${seen_accounts[$current_account]}" ]]; then
        echo "Account '$ENV_GITHUB_ACCOUNT' was not found." >&2
        echo "Try: gh auth login to login with $ENV_GITHUB_ACCOUNT" >&2
        return 1
    fi

    # Mark as seen
    seen_accounts["$current_account"]=1

    # Switch and try again
    gh_original auth switch
  done

  # Run the original gh command with passed arguments
  gh_original "$@"
}
