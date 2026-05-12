defmodule GraceJobs.Pipeline.SourceProducer do
  @moduledoc """
  GenStage producer that buffers "scrape task" tuples and emits them on
  downstream demand. A scrape task is `{source_atom, opts_keyword}`,
  e.g. `{:remoteok, []}` or `{:hackernews, [thread_id: 12345]}`.
  """
  use GenStage

  @type task :: {atom(), keyword()}

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenStage.start_link(__MODULE__, :ok, name: name)
  end

  @doc "Enqueue one scrape task. Returns :ok."
  def enqueue(server \\ __MODULE__, task) do
    GenStage.cast(server, {:enqueue, task})
  end

  @doc "Enqueue many tasks at once."
  def enqueue_many(server \\ __MODULE__, tasks) when is_list(tasks) do
    GenStage.cast(server, {:enqueue_many, tasks})
  end

  @impl true
  def init(:ok), do: {:producer, %{queue: :queue.new(), pending_demand: 0}}

  @impl true
  def handle_cast({:enqueue, task}, state) do
    state = %{state | queue: :queue.in(task, state.queue)}
    dispatch(state, [])
  end

  def handle_cast({:enqueue_many, tasks}, state) do
    queue = Enum.reduce(tasks, state.queue, fn t, q -> :queue.in(t, q) end)
    dispatch(%{state | queue: queue}, [])
  end

  @impl true
  def handle_demand(incoming, state) do
    state = %{state | pending_demand: state.pending_demand + incoming}
    dispatch(state, [])
  end

  defp dispatch(%{pending_demand: 0} = state, events), do: {:noreply, Enum.reverse(events), state}

  defp dispatch(state, events) do
    case :queue.out(state.queue) do
      {{:value, task}, q} ->
        dispatch(
          %{state | queue: q, pending_demand: state.pending_demand - 1},
          [task | events]
        )

      {:empty, _} ->
        {:noreply, Enum.reverse(events), state}
    end
  end
end
