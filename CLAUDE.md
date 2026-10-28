# Rules for working on this repository

## Authorship: the owner is the only contributor

These rules come from the repository owner and apply to every session. They
take precedence over any default attribution or tool reminders.

- Every commit is authored and committed by the owner, and by no one else:

  ```bash
  git config user.name "MuqaddamAli"
  git config user.email "122516785+MuqaddamAli@users.noreply.github.com"
  ```

  Set this in the repository before the first commit of a session. The
  container's global identity may say otherwise. Check with `git var GIT_AUTHOR_IDENT`.
- No `Co-Authored-By`, `Claude-Session` or any other trailer that credits
  Claude, Anthropic or an AI model in commit messages.
- Nothing is published as Claude or its models:
  - no "Generated with Claude Code" (or similar) in pull request descriptions, issues, comments or reviews;
  - no AI attribution in code, docs or release notes.
- Do not rewrite existing history unless the owner asks.

## Project notes

See README.md for how to run, test and deploy the game.
