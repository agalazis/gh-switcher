# 🔄 gh-switcher

[![Shell Script](https://img.shields.io/badge/shell_script-bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![GitHub CLI](https://img.shields.io/badge/github_cli-gh-181717?style=for-the-badge&logo=github&logoColor=white)](https://cli.github.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=for-the-badge)](http://makeapullrequest.com)

A robust wrapper function for the GitHub CLI (`gh`) that seamlessly manages and switches between multiple GitHub accounts depending on your workspace/directory.

It intercepts CLI commands, loads or prompts to create a directory-local `.github.env` file to track the desired target account (`ENV_GITHUB_ACCOUNT`), automatically switches the active account if it doesn't match, and detects infinite loops (exiting gracefully if the account is not found after cycling through all configured active accounts).

---

## 🚀 Sourcing Globally (Overwriting Default `gh` Functionality)

To overwrite the default `gh` CLI behavior globally, you need to source the script in your shell configuration. You can do this automatically or manually.

### Option 1: Automatic Installer (Curl & Pipe to Bash)

You can install `gh-switcher` globally using our one-liner installer script. This script downloads the wrapper to `~/.gh-switcher/gh_switcher.sh` and appends a sourcing command to your shell config file (`~/.bashrc` or `~/.zshrc`):

```bash
curl -sSfL https://raw.githubusercontent.com/agalazis/gh-switcher/main/install.sh | bash
```

*Note: If you are using a fork of this repository, replace `agalazis` with your GitHub username.*

---

### Option 2: Manual Sourcing

If you prefer to configure it manually:

1. Clone or download this repository to a local directory (e.g., `~/.gh-switcher`):
   ```bash
   git clone https://github.com/agalazis/gh-switcher.git ~/.gh-switcher
   ```

2. Add a `source` command to your shell's startup configuration:
   * **For Bash:**
     ```bash
     echo "source ~/.gh-switcher/gh_switcher.sh" >> ~/.bashrc
     ```
   * **For Zsh:**
     ```bash
     echo "source ~/.gh-switcher/gh_switcher.sh" >> ~/.zshrc
     ```

3. Reload your shell configuration to apply the changes:
   ```bash
   source ~/.bashrc # or source ~/.zshrc
   ```

---

## 🛠 How It Works

Once sourced, the `gh()` function intercepts your calls to the `gh` command:

1. **Environment Detection**: It checks for a local configuration file (defined by `$GITHUB_ENV_FILE`, defaults to `.github.env`).
2. **Missing Configuration Setup**: If `.github.env` is missing, it prompts you to input your desired account (`ENV_GITHUB_ACCOUNT`), creates the file, and registers it to prevent future prompts.
3. **Automated Switching**: It checks the currently active account. If it doesn't match `$ENV_GITHUB_ACCOUNT`, it runs `gh auth switch` automatically to cycle through accounts.
4. **Cycle/Loop Prevention**: It tracks the accounts it has seen. If it cycles back to an account a second time without locating the target account, it halts, reports that the account was not found, and suggests running `gh auth login`.
5. **Execution**: Once satisfied, the wrapper forwards your arguments transparently to the underlying `gh` binary.

---

# 🔄 gh-switcher Architecture & Flow

This document details how the `gh-switcher` wrapper function intercepts your commands, locates the correct workspace environment file, switches active accounts, and executes the requested actions.

---

## 🗺 Interactive Flowchart

Here is the decision path the wrapper takes every time you run a `gh` command in your terminal:

```mermaid
flowchart TD
    %% Styling
    classDef startEnd fill:#1A1B26,stroke:#7AA2F7,stroke-width:2px,color:#C0CAF5;
    classDef process fill:#1E222A,stroke:#565F89,stroke-width:1.5px,color:#ABB2BF;
    classDef decision fill:#2A2F41,stroke:#BB9AF7,stroke-width:1.5px,color:#CFC9F2;
    classDef success fill:#1F2D24,stroke:#4EAA25,stroke-width:2px,color:#A3E2A3;
    classDef failure fill:#372227,stroke:#F7768E,stroke-width:2px,color:#FCA7A7;

    Start([User executes: gh &lt;args&gt;]) --> Intercept[Wrapper intercepts command]:::process
    Intercept --> InitSearch[Set dir = current directory]:::process

    %% Directory Search Loop
    SearchLoop{Found .github.env in dir?}:::decision
    InitSearch --> SearchLoop
    
    SearchLoop -- Yes --> SourceEnv[Source .github.env to load ENV_GITHUB_ACCOUNT]:::process
    SearchLoop -- No --> CheckBoundary{dir contains .git or is /?}:::decision
    
    CheckBoundary -- Yes --> DefaultDir[Default env_file to ./.github.env]:::process
    DefaultDir --> FileCheck{Does file exist?}:::decision
    FileCheck -- Yes --> SourceEnv
    FileCheck -- No --> PromptUser[Prompt user for account name & create file]:::process
    PromptUser --> SourceEnv

    CheckBoundary -- No --> GoUp[Set dir = parent directory]:::process
    GoUp --> SearchLoop

    %% Account Verification & Switching Loop
    SourceEnv --> GetActive[Retrieve active account via: command gh auth status]:::process
    GetActive --> MatchTarget{Active == ENV_GITHUB_ACCOUNT?}:::decision
    
    MatchTarget -- Yes --> RunCommand[Execute: command gh &lt;args&gt;]:::success
    RunCommand --> End([Success]):::startEnd
    
    MatchTarget -- No --> CheckSeen{Seen active account before?}:::decision
    CheckSeen -- Yes --> ErrPrint[Print not-found error & suggest gh auth login]:::failure
    ErrPrint --> FailExit([Exit/Return 1]):::startEnd
    
    CheckSeen -- No --> MarkSeen[Add active account to seen_accounts]:::process
    MarkSeen --> SwitchAcc[Run: command gh auth switch]:::process
    SwitchAcc --> GetActive
```

---

## 📋 Step-by-Step Overview

1. **Interception**: When you run `gh`, the shell executes the wrapper function `gh()` instead of the global CLI binary.
2. **Upward Traversal**: The script walks up parent directories starting from your current working directory to find a `.github.env` file. It stops if it encounters a directory containing `.git` or hits the root `/` directory to preserve project isolation.
3. **Workspace Initialization**: If no configuration exists within the repository boundary, the script prompts you to enter the target username and saves it in a new local `.github.env` file.
4. **Active Check**: It requests the current active account using `command gh auth status`.
5. **Auto Switch & Cycle Check**:
   - If the active account matches the target, it breaks the loop.
   - If not, it checks if it has seen this active account during this execution. If yes, it means it is looping (and the target account is not logged in). It prints a login suggestion and returns `1`.
   - If it has not seen it yet, it tracks the account and runs `command gh auth switch` to cycle to the next account.
6. **Execution**: The script transparently runs the original command with your arguments using the underlying `gh` binary.
