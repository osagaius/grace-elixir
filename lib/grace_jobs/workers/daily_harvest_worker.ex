defmodule GraceJobs.Workers.DailyHarvestWorker do
  @moduledoc """
  Oban cron worker that kicks off the daily harvest. Enqueues one
  scrape task per source into the GenStage producer; the pipeline
  takes it from there.

  Target: ~100 jobs/day across the configured sources.
  """
  use Oban.Worker, queue: :harvest, max_attempts: 3

  alias GraceJobs.Pipeline.SourceProducer

  @default_sources [
    {:remoteok, []},
    {:weworkremotely, []},
    {:hackernews, [limit: 60]}
  ]

  @impl true
  def perform(%Oban.Job{args: args}) do
    sources = decode_sources(args["sources"]) || @default_sources
    SourceProducer.enqueue_many(sources)
    :ok
  end

  defp decode_sources(nil), do: nil

  defp decode_sources(list) when is_list(list) do
    Enum.map(list, fn
      [src, opts] when is_binary(src) -> {String.to_existing_atom(src), atomise_keys(opts)}
      src when is_binary(src) -> {String.to_existing_atom(src), []}
    end)
  end

  defp atomise_keys(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)

  defp atomise_keys(_), do: []
end
