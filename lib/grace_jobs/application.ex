defmodule GraceJobs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    base_children = [
      GraceJobsWeb.Telemetry,
      GraceJobs.Repo,
      {DNSCluster, query: Application.get_env(:grace_jobs, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GraceJobs.PubSub},
      {Oban, Application.fetch_env!(:grace_jobs, Oban)}
    ]

    pipeline_children =
      if Application.get_env(:grace_jobs, :start_pipeline?, true) do
        [GraceJobs.Pipeline.Supervisor]
      else
        []
      end

    children = base_children ++ pipeline_children ++ [GraceJobsWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GraceJobs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GraceJobsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
