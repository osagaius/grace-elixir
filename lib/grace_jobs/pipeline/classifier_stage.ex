defmodule GraceJobs.Pipeline.ClassifierStage do
  @moduledoc """
  ProducerConsumer that calls the configured LLM client to add
  `role`, `seniority`, and merged `tags` to each raw job. Failures
  pass through with whatever fields the source provided.
  """
  use GenStage
  require Logger

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    subscribe_to = Keyword.get(opts, :subscribe_to, [])
    GenStage.start_link(__MODULE__, subscribe_to, name: name)
  end

  @impl true
  def init(subscribe_to), do: {:producer_consumer, :ok, subscribe_to: subscribe_to}

  @impl true
  def handle_events(jobs, _from, state) do
    classified = Enum.map(jobs, &classify/1)
    {:noreply, classified, state}
  end

  defp classify(raw) do
    client = Application.fetch_env!(:grace_jobs, :llm)[:client]

    case client.classify(raw) do
      {:ok, %{role: role, seniority: sen, tags: tags}} ->
        merged_tags = (List.wrap(raw[:tags]) ++ tags) |> Enum.uniq() |> Enum.take(12)
        Map.merge(raw, %{role: role, seniority: sen, tags: merged_tags})

      {:error, reason} ->
        Logger.warning("LLM classify failed: #{inspect(reason)} — passing through raw")
        raw
    end
  end
end
