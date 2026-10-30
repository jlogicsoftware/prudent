---
name: git-pr
description: Prepare commits and create or update pull requests for Prudent, including selecting the authorized GitHub identity and access method.
---

# Commits and pull requests for Prudent

Follow `AGENTS.md` for explicit commit/push approval, branch naming, staging individual paths,
checking the index, commit identity, and protecting other people's changes. Never use `main` or
`master` for a commit.

For GitHub actions on `jlogicsoftware/prudent`, verify the active account is `konter-dev` before
creating or changing a PR or other repository resource. Use these access paths in order:

1. Use the terminal or CLI if it can authenticate as `konter-dev`.
2. Otherwise, check GitHub Desktop for the `konter-dev` account and use it if available.
3. Otherwise, use Chrome's **Adam** profile (the browser window identifies it as Adam), verify
   GitHub is signed in as `konter-dev` / Adam Konter, and perform the action there. Browser
   extensions may be connected to a different Chrome profile; verify the actual window and GitHub
   account instead of assuming an extension's session is Adam.

If none is available, ask the user to sign in as `konter-dev`; never substitute a different GitHub
account. Interactive authentication is not a retry problem. After creating a PR, attach it to the
current Codex task and report its link.
