---
name: linkbot-start
description: Boot the Linkbot Phoenix LiveView app (mix phx.server) and open the jobs dashboard in the default browser. Use when the user asks to "start linkbot", "open the dashboard", "run the app", or anything similar in this repo.
---

# linkbot-start

Boots the Phoenix app in the current workspace (the repo root containing
`mix.exs`) and opens the LiveView dashboard so the user can watch the Claude
session apply to jobs.

## Steps

1. **Determine the port.** The default port is configured in
   `config/runtime.exs` (currently `4050`). It can be overridden with the
   `PORT` env var. Detect the active port by reading that file — grep for
   `String.to_integer(System.get_env("PORT"`. If you cannot determine it, fall
   back to `4050`.

2. **Skip the boot if it's already running.** Run
   `lsof -iTCP:<port> -sTCP:LISTEN -n -P`. If something is already listening on
   the port, fetch `http://127.0.0.1:<port>/` and look for the `Linkbot`
   title — if present, jump straight to step 5 (no need to start again). If
   another app is on the port and you cannot reach a Linkbot response, stop
   and tell the user — do not kill the foreign process.

3. **Start the server in the background** with the Bash tool's
   `run_in_background: true`. The exact command:

   ```bash
   mix phx.server
   ```

   Run it from the repo root (the directory containing `mix.exs`). Use an
   absolute path with `cd` if your current shell isn't already there.

   Capture the background shell id so the user can stop it later (mention
   `BashKill` / `BashOutput` only if they ask).

4. **Wait until the port is listening.** Poll every 500 ms (no `sleep`-loops
   in Bash — use the `Monitor` tool with `until lsof -iTCP:<port> -sTCP:LISTEN
   -n -P >/dev/null; do sleep 0.5; done`). Cap at 30 s — if the port still
   isn't open by then, run `BashOutput` on the server shell, surface any
   compile/boot errors, and stop.

5. **Open the dashboard.** Run:

   ```bash
   open http://localhost:<port>/
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
