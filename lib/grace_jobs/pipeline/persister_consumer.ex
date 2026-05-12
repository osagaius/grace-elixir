defmodule GraceJobs.Pipeline.PersisterConsumer do
  @moduledoc """
  Consumer that upserts each classified job into Postgres via the Jobs
  context (which also broadcasts on the `jobs` PubSub topic).
  """
  use GenStage
  require Logger
  alias GraceJobs.Jobs

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    subscribe_to = Keyword.get(opts, :subscribe_to, [])
    GenStage.start_link(__MODULE__, subscribe_to, name: name)
  end

  @impl true
  def init(subscribe_to), do: {:consumer, :ok, subscribe_to: subscribe_to}

  @impl true
  def handle_events(jobs, _from, state) do
    Enum.each(jobs, fn job ->
      case Jobs.upsert_job(job) do
        {:ok, _} -> :ok
        {:error, e} -> Logger.warning("persist failed for #{inspect(job[:url])}: #{inspect(e)}")
      end
    end)

    {:noreply, [], state}
  end
end
