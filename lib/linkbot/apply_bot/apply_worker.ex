defmodule Linkbot.ApplyBot.ApplyWorker do
  @moduledoc """
  Oban worker for one job application.

  Drives the singleton `Linkbot.ApplyBot.SessionRunner`: subscribes to
  its PubSub topic, calls `run/2`, and blocks until the spawned Claude
  process emits `:exited`. The outcome is decided by reading
  `jobs.status` — the prompt's STEP 6 is what writes `'applied'`,
  so if the row isn't `applied` after the session exits we return
  `{:error, ...}` and Oban retries up to `max_attempts`.

  Queue concurrency is pinned to 1 in `config :linkbot, Oban`, so two
  workers can't fight over the SessionRunner.
  """

  use Oban.Worker,
    queue: :applybot,
    max_attempts: 3,
    unique: [
      period: 86_400,
      fields: [:args],
      keys: [:job_url],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Linkbot.ApplyBot.SessionRunner
  alias Linkbot.Jobs.Job
  alias Linkbot.Repo
  import Ecto.Query

  # Hard cap per attempt. A real run is ~5–15 min; give it room.
  @run_timeout_ms 30 * 60_000

  @impl Oban.Worker
  def timeout(_job), do: @run_timeout_ms + 60_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_url" => job_url, "resume_url" => resume_url}}) do
    if applied?(job_url) do
      :ok
    else
      :ok = SessionRunner.subscribe()

      case SessionRunner.run(job_url, resume_url) do
        {:ok, _os_pid} ->
          await_exit_and_check(job_url)

        {:error, :already_running} ->
          # Concurrency 1 means Oban itself won't double-dispatch; this
          # only fires when something outside Oban (a manual run via the
          # form, a test) is using the runner. Let Oban try later.
          {:snooze, 30}
      end
    end
  end

  defp await_exit_and_check(job_url) do
    receive do
      {:exited, %{status: 0}} ->
        if applied?(job_url) do
          :ok
        else
          {:error, :session_exited_without_applied_status}
        end

      {:exited, %{status: status}} ->
        {:error, {:claude_exit, status}}
    after
      @run_timeout_ms ->
        SessionRunner.stop_session()
        {:error, :timeout}
    end
  end

  defp applied?(job_url) do
    Repo.exists?(from j in Job, where: j.url == ^job_url and j.status == "applied")
  end
end
