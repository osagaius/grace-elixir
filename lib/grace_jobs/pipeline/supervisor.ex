defmodule GraceJobs.Pipeline.Supervisor do
  @moduledoc """
  Supervises the GenStage job pipeline:

      SourceProducer  →  ScrapeStage  →  ClassifierStage  →  PersisterConsumer

  All stages are demand-driven. The DailyHarvestWorker pushes "scrape
  task" tuples (`{:remoteok, opts}`, etc.) into the producer, which emits
  them to the scrape stage when downstream demand arrives.
  """
  use Supervisor

  alias GraceJobs.Pipeline

  def start_link(_), do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(_) do
    children = [
      {Pipeline.SourceProducer, name: Pipeline.SourceProducer},
      {Pipeline.ScrapeStage, [name: Pipeline.ScrapeStage, subscribe_to: [Pipeline.SourceProducer]]},
      {Pipeline.ClassifierStage,
       [name: Pipeline.ClassifierStage, subscribe_to: [{Pipeline.ScrapeStage, max_demand: 10}]]},
      {Pipeline.PersisterConsumer,
       [name: Pipeline.PersisterConsumer, subscribe_to: [{Pipeline.ClassifierStage, max_demand: 5}]]}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
