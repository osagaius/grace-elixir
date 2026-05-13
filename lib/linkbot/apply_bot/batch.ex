defmodule Linkbot.ApplyBot.Batch do
  @moduledoc """
  Sequential queue runner for `Linkbot.ApplyBot.SessionRunner`.

  The SessionRunner is a singleton that handles ONE application at a
  time. This GenServer drives it through a list of job URLs: it kicks
  off the first run, listens to the `apply_session` PubSub topic, and
  on every `:exited` broadcast dequeues the next URL and starts the
  next run. When the queue is empty it stops itself.

  Start it with:

      Linkbot.ApplyBot.Batch.start_link(
        urls: ["https://jobs.ashbyhq.com/...", ...],
        resume_url: "https://drive.google.com/file/d/.../view"
      )

  Inspect progress with `Linkbot.ApplyBot.Batch.status/0`.
  """

  use GenServer
  require Logger

  alias Linkbot.ApplyBot.SessionRunner

  @topic "apply_session"

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Unlinked starter. Use this when launching from a remote shell / `:rpc.call`,
  so the GenServer is not torn down when the calling client exits.
  """
  def start(opts) do
    GenServer.start(__MODULE__, opts, name: __MODULE__)
  end

  def status, do: GenServer.call(__MODULE__, :status)

  def stop_batch, do: GenServer.call(__MODULE__, :stop_batch)

  # ── GenServer ───────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    urls = Keyword.fetch!(opts, :urls)
    resume_url = Keyword.fetch!(opts, :resume_url)

    Phoenix.PubSub.subscribe(Linkbot.PubSub, @topic)

    state = %{
      pending: urls,
      done: [],
      current: nil,
      resume_url: resume_url,
      started_at: DateTime.utc_now()
    }

    {:ok, state, {:continue, :start_next}}
  end

  @impl true
  def handle_continue(:start_next, %{pending: []} = state) do
    Logger.info("[batch] queue drained — #{length(state.done)} job(s) processed")
    {:stop, :normal, state}
  end

  def handle_continue(:start_next, %{pending: [url | rest]} = state) do
    case SessionRunner.run(url, state.resume_url) do
      {:ok, os_pid} ->
        Logger.info("[batch] started apply for #{url} (pid=#{os_pid})")
        {:noreply, %{state | current: url, pending: rest}}

      {:error, :already_running} ->
        Logger.warning(
          "[batch] SessionRunner busy on a foreign job; #{url} stays queued, waiting for :exited"
        )

        {:noreply, state}

      other ->
        Logger.error("[batch] SessionRunner.run/2 returned #{inspect(other)} for #{url}")
        {:noreply, %{state | done: [{url, {:error, other}} | state.done]},
         {:continue, :start_next}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       current: state.current,
       pending: state.pending,
       done: Enum.reverse(state.done),
       remaining: length(state.pending),
       started_at: state.started_at
     }, state}
  end

  def handle_call(:stop_batch, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:exited, %{status: status}}, %{current: url} = state) when not is_nil(url) do
    Logger.info("[batch] apply for #{url} exited (status=#{status})")
    new_state = %{state | done: [{url, {:exited, status}} | state.done], current: nil}
    {:noreply, new_state, {:continue, :start_next}}
  end

  def handle_info({:exited, %{status: status}}, %{current: nil} = state) do
    # Someone else's session exited (we were waiting because SessionRunner
    # was busy when we tried to start). Try the head of the queue now.
    Logger.info("[batch] foreign session exited (status=#{status}); attempting our next start")
    {:noreply, state, {:continue, :start_next}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
