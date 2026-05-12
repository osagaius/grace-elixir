# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :grace_jobs,
  ecto_repos: [GraceJobs.Repo],
  generators: [timestamp_type: :utc_datetime]

# Oban — daily harvest cron at 09:00 UTC
config :grace_jobs, Oban,
  repo: GraceJobs.Repo,
  engine: Oban.Engines.Basic,
  queues: [harvest: 4, default: 10],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 9 * * *", GraceJobs.Workers.DailyHarvestWorker}
     ]}
  ]

# Pluggable scraper / LLM modules — overridden in test
config :grace_jobs, :scrapers,
  remoteok: GraceJobs.Scrapers.RemoteOK,
  weworkremotely: GraceJobs.Scrapers.WeWorkRemotely,
  hackernews: GraceJobs.Scrapers.HackerNews

config :grace_jobs, :llm,
  client: GraceJobs.LLM.Ollama,
  model: System.get_env("OLLAMA_MODEL", "llama3.2:3b"),
  base_url: System.get_env("OLLAMA_URL", "http://localhost:11434")

# Anthropic computer-use (optional, for harder boards)
config :grace_jobs, :anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: "claude-opus-4-7",
  base_url: "https://api.anthropic.com"

# Configure the endpoint
config :grace_jobs, GraceJobsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GraceJobsWeb.ErrorHTML, json: GraceJobsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GraceJobs.PubSub,
  live_view: [signing_salt: "67fxgsaU"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  grace_jobs: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  grace_jobs: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
