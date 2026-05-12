defmodule GraceJobs.Repo do
  use Ecto.Repo,
    otp_app: :grace_jobs,
    adapter: Ecto.Adapters.Postgres
end
