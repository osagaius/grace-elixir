import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :grace_jobs, GraceJobs.Repo,
  username: System.get_env("PGUSER", "osayame"),
  password: System.get_env("PGPASSWORD", ""),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "grace_jobs_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :grace_jobs, GraceJobsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "8rYr2JRY3IpFSuC8vfCyUvc/QNsYrBzPjWzRr2KR1l5WHHEodQHzEtsyVq3xaqin",
  server: false

# Oban — testing mode (no queues, no cron, jobs created but not executed)
config :grace_jobs, Oban,
  testing: :manual,
  repo: GraceJobs.Repo,
  queues: false,
  plugins: false

# Don't auto-start the GenStage pipeline in tests; tests that need it
# start it explicitly via `start_supervised!(GraceJobs.Pipeline.Supervisor)`.
config :grace_jobs, :start_pipeline?, false

# Use Mox-backed implementations in tests
config :grace_jobs, :scrapers,
  remoteok: GraceJobs.ScraperMock,
  weworkremotely: GraceJobs.ScraperMock,
  hackernews: GraceJobs.ScraperMock

config :grace_jobs, :llm,
  client: GraceJobs.LLMMock,
  model: "test-model",
  base_url: "http://localhost:11434"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
