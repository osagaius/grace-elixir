---
name: linkbot-start
description: Boot the Linkbot Phoenix LiveView app (mix phx.server) and open the jobs dashboard in the default browser. Use when the user asks to "start linkbot", "open the dashboard", "run the app", or anything similar in this repo.
---

# linkbot-start

Boots the consolidated Phoenix app in `/Users/osayame/.superset/worktrees/grace-elixir/agreeable-starflower`
and opens the Linkbot dashboard so the user can watch the Claude session
apply to jobs.

## Steps

1. **Determine the ports.** 
   - Linkbot: `4050` (configured in `config/dev.exs`)
   - Grace Jobs: `4000` (configured in `config/dev.exs`)

2. **Skip the boot if it's already running.** Run
   `lsof -iTCP:4050 -sTCP:LISTEN -n -P`. If something is already listening on
   the port, fetch `http://127.0.0.1:4050/` and look for the `Linkbot`
   title.

3. **Start the server in the background** with the Bash tool's
   `run_in_background: true`. The exact command:

   ```bash
   cd /Users/osayame/.superset/worktrees/grace-elixir/agreeable-starflower && mix phx.server
   ```

4. **Wait until the port is listening.** Poll every 500 ms.

5. **Open the dashboards.** Run:

   ```bash
   open http://localhost:4050/
   open http://localhost:4000/
   ```

   on macOS. (On Linux: `xdg-open`; on Windows/WSL: `cmd.exe /c start`.)

6. **Report back** with one short line:

   > Linkbot is running at http://localhost:<port>/ — opened in your browser.

   Mention the background shell id so the user can stop it via `/stop` or
   `BashKill` if they want.

## Notes

- The configured port may not be `4000` even if the user asks for that —
  another Phoenix app on this machine already holds 4000, so the default was
  moved to 4050 in `config/runtime.exs`. If the user explicitly wants 4000,
  run `lsof -iTCP:4000 -sTCP:LISTEN -n -P` first; if free, ask whether to
  edit `config/runtime.exs` to switch back — do NOT silently kill whatever is
  using 4000.
- The app uses SQLite at `linkbot_dev.db` in the project root. `mix
  ecto.create && mix ecto.migrate` only needs to be run once; the supervised
  `Ecto.Migrator` runs migrations on each boot.
- The dashboard at `/` is a Phoenix LiveView (`LinkbotWeb.JobsLive`). It
  lists every row in the `jobs` table and streams the Claude session's
  stdout into a live log panel. Clicking ▶ Run session inside the page kicks
  off `claude --dangerously-skip-permissions --chrome` via
  `Linkbot.SessionRunner`.
