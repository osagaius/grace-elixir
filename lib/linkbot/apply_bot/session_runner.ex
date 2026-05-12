defmodule Linkbot.ApplyBot.SessionRunner do
  @moduledoc """
  Spawns and supervises a single `claude --dangerously-skip-permissions --chrome`
  process whose job is to apply to ONE posted job using the resume at
  `resume_url`. Inspired by `Linkbot.SessionRunner`, but scoped to a single
  application rather than a whole search.
  """

  use GenServer
  require Logger

  alias Linkbot.ApplyBot.SessionPrompt

  @topic "apply_session"
  @max_log_lines 500
  @log_file "/tmp/applybot.log"

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Linkbot.PubSub, @topic)

  @doc """
  Start a Claude session that applies to `job_url` using the resume at
  `resume_url`.
  """
  def run(job_url, resume_url) when is_binary(job_url) and is_binary(resume_url),
    do: GenServer.call(__MODULE__, {:run, job_url, resume_url})

  def stop_session, do: GenServer.call(__MODULE__, :stop_session)

  def status, do: GenServer.call(__MODULE__, :status)

  # ── GenServer ───────────────────────────────────────────────────────────────

  @impl true
  def init(_),
    do:
      {:ok,
       %{
         port: nil,
         os_pid: nil,
         job_url: nil,
         resume_url: nil,
         log: [],
         steps: MapSet.new(),
         artifacts: [],
         started_at: nil
       }}

  @impl true
  def handle_call({:run, _job_url, _resume_url}, _from, %{port: port} = state)
      when is_port(port) do
    {:reply, {:error, :already_running}, state}
  end

  def handle_call({:run, job_url, resume_url}, _from, state) do
    {bin, args} = build_command(job_url, resume_url)

    port =
      Port.open(
        {:spawn_executable, bin},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:args, args},
          {:line, 4096}
        ]
      )

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    started_at = DateTime.utc_now()

    broadcast(:started, %{
      job_url: job_url,
      resume_url: resume_url,
      started_at: started_at,
      os_pid: os_pid
    })

    started_entry = log_entry("[runner] apply session started: #{job_url}")
    tee_to_file(started_entry)

    new_state = %{
      state
      | port: port,
        os_pid: os_pid,
        job_url: job_url,
        resume_url: resume_url,
        started_at: started_at,
        log: [started_entry],
        steps: MapSet.new(),
        artifacts: []
    }

    {:reply, {:ok, os_pid}, new_state}
  end

  def handle_call(:stop_session, _from, %{port: nil} = state),
    do: {:reply, :not_running, %{state | job_url: nil, resume_url: nil, started_at: nil}}

  def handle_call(:stop_session, _from, %{port: port, os_pid: os_pid} = state) do
    if os_pid, do: System.cmd("kill", ["-TERM", Integer.to_string(os_pid)])
    Port.close(port)
    broadcast(:stopped, %{reason: :user})

    {:reply, :ok,
     %{
       state
       | port: nil,
         os_pid: nil,
         job_url: nil,
         resume_url: nil,
         started_at: nil
     }}
  end

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       running?: is_port(state.port),
       job_url: state.job_url,
       resume_url: state.resume_url,
       started_at: state.started_at,
       log: Enum.reverse(state.log),
       steps: state.steps,
       artifacts: Enum.reverse(state.artifacts)
     }, state}
  end

  @impl true
  def handle_info({port, {:data, {_eol, line}}}, %{port: port} = state) do
    entry = log_entry(line)
    broadcast(:log, entry)
    tee_to_file(entry)

    state =
      state
      |> Map.update!(:log, &trim([entry | &1]))
      |> ingest_marker(line)

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    entry = log_entry("[runner] apply session exited (status=#{status})")
    broadcast(:exited, %{status: status})
    tee_to_file(entry)
    {:noreply, %{state | port: nil, os_pid: nil, log: trim([entry | state.log])}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp build_command(job_url, resume_url) do
    case Application.get_env(:linkbot, __MODULE__, [])[:command] do
      {:fun, fun} when is_function(fun, 2) ->
        fun.(job_url, resume_url)

      {bin, args} when is_binary(bin) and is_list(args) ->
        {bin, args}

      nil ->
        conn = repo_conn()
        prompt = SessionPrompt.render(job_url, resume_url, conn)
        bin = System.find_executable("claude") || "claude"
        {bin, ["--dangerously-skip-permissions", "--chrome", "--print", prompt]}
    end
  end

  defp repo_conn do
    cfg = Linkbot.Repo.config()

    %{
      database: Keyword.fetch!(cfg, :database),
      hostname: Keyword.get(cfg, :hostname, "localhost"),
      port: Keyword.get(cfg, :port, 5432),
      username: Keyword.get(cfg, :username, System.get_env("USER", "postgres")),
      password: Keyword.get(cfg, :password, "")
    }
  end

  defp log_entry(line) when is_binary(line),
    do: %{at: DateTime.utc_now(), line: line}

  defp trim(log) when length(log) > @max_log_lines,
    do: Enum.take(log, @max_log_lines)

  defp trim(log), do: log

  defp broadcast(event, payload),
    do: Phoenix.PubSub.broadcast(Linkbot.PubSub, @topic, {event, payload})

  # ── Step / artifact markers ───────────────────────────────────────────────
  #
  # The session prompt requires Claude to emit two kinds of structured lines
  # so this harness can verify what was completed:
  #
  #   [step] N/T <slug>        — checkpoint at end of step N of T
  #   [artifact] <kind>: <path> — file Claude saved (screenshot, html, …)
  #
  # Anything matching either pattern is recorded in state so status/0 can
  # surface it to the test suite and the LiveView dashboard.

  defp ingest_marker(state, line) do
    cond do
      step = parse_step(line) ->
        broadcast(:step, step)
        Map.update!(state, :steps, &MapSet.put(&1, step.slug))

      artifact = parse_artifact(line) ->
        broadcast(:artifact, artifact)
        Map.update!(state, :artifacts, &[artifact | &1])

      true ->
        state
    end
  end

  defp parse_step(line) do
    case Regex.run(~r/\[step\]\s+(\d+)\/(\d+)\s+([\w\-]+)/, line) do
      [_, n, t, slug] ->
        %{n: String.to_integer(n), total: String.to_integer(t), slug: slug}

      _ ->
        nil
    end
  end

  defp parse_artifact(line) do
    case Regex.run(~r/\[artifact\]\s+(\w+):\s*(\S.+?)\s*$/, line) do
      [_, kind, path] -> %{kind: kind, path: path}
      _ -> nil
    end
  end

  # Append each log line to @log_file. Best-effort — never crashes the
  # GenServer if the file isn't writable.
  defp tee_to_file(%{at: at, line: line}) do
    path = Application.get_env(:linkbot, __MODULE__, [])[:log_file] || @log_file

    ts = Calendar.strftime(at, "%Y-%m-%d %H:%M:%S")
    _ = File.write(path, "#{ts} #{line}\n", [:append])
    :ok
  end
end
