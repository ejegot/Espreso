# Repository workflow

- For each new, independent implementation task, create a descriptive `ej/<short-kebab-slug>` branch in the user's current checkout before editing files. Do not create a separate worktree.
- Keep task changes on that branch so they are visible in the user's `git status`. Do not commit or push unless explicitly asked.
- Continue on the current branch when the user is continuing the same task. If the checkout has unrelated uncommitted changes before starting a new task, preserve them and ask before switching branches.
- Do not invent ticket numbers. Use a real ticket number only when the user provides one.
