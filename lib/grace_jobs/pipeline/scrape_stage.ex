defmodule GraceJobs.Pipeline.ScrapeStage do
  @moduledoc """
  ProducerConsumer that takes scrape tasks `{source, opts}` and emits the
  raw jobs returned by the corresponding scraper.
  """
  use GenStage
  require Logger

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    subscribe_to = Keyword.get(opts, :subscribe_to, [])
    GenStage.start_link(__MODULE__, subscribe_to, name: name)
  end

  @impl true
  def init(subscribe_to) do
    {:producer_consumer, :ok, subscribe_to: subscribe_to}
  end

  @impl true
  def handle_events(events, _from, state) do
    raw_jobs =
      events
      |> Enum.flat_map(&run/1)
      |> Enum.uniq_by(&{&1.source, &1.external_id})

    {:noreply, raw_jobs, state}
  end

  defp run({source, opts}) do
    mod = scraper_for(source)

    case mod.fetch(opts) do
      {:ok, jobs} ->
        Logger.info("scraper #{inspect(source)} returned #{length(jobs)} jobs")
        jobs

      {:error, reason} ->
        Logger.warning("scraper #{inspect(source)} failed: #{inspect(reason)}")
        []
    end
  end

  defp scraper_for(source) do
    Application.fetch_env!(:grace_jobs, :scrapers)
    |> Keyword.fetch!(source)
  end
end
