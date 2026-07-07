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
