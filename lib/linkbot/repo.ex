defmodule Linkbot.Repo do
  use Ecto.Repo,
    otp_app: :linkbot,
    adapter: Ecto.Adapters.Postgres
end
