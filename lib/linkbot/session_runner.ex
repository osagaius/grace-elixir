defmodule Linkbot.SessionRunner do
  @moduledoc """
  Spawns and supervises a single `claude --dangerously-skip-permissions --chrome`
  process. The session is given a prompt that tells it to drive LinkedIn via the
  Chrome MCP and write each job into the local SQLite db with the `sqlite3` CLI.
  """

  use GenServer
  require Logger

  alias Linkbot.SessionPrompt

  @topic "session"
  @max_log_lines 500

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Linkbot.PubSub, @topic)

  @doc "Start a Claude session with the given hardcoded search criteria."
  def run(query \\ SessionPrompt.default_query()),
    do: GenServer.call(__MODULE__, {:run, query})

  def stop_session, do: GenServer.call(__MODULE__, :stop_session)

  def status, do: GenServer.call(__MODULE__, :status)

  # ── GenServer ───────────────────────────────────────────────────────────────

  @impl true
  def init(_), do: {:ok, %{port: nil, os_pid: nil, query: nil, log: [], started_at: nil}}

  @impl true
  def handle_call({:run, _query}, _from, %{port: port} = state) when is_port(port) do
    {:reply, {:error, :already_running}, state}
  end

  def handle_call({:run, query}, _from, state) do
    {bin, args} = build_command(query)

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
    broadcast(:started, %{query: query, started_at: started_at, os_pid: os_pid})

    new_state = %{
      state
      | port: port,
        os_pid: os_pid,
        query: query,
        started_at: started_at,
        log: [log_entry("[runner] session started: #{query}")]
    }

    {:reply, {:ok, os_pid}, new_state}
  end

  def handle_call(:stop_session, _from, %{port: nil} = state),
    do: {:reply, :not_running, %{state | query: nil, started_at: nil}}

  def handle_call(:stop_session, _from, %{port: port, os_pid: os_pid} = state) do
    if os_pid, do: System.cmd("kill", ["-TERM", Integer.to_string(os_pid)])
    Port.close(port)
    broadcast(:stopped, %{reason: :user})
    {:reply, :ok, %{state | port: nil, os_pid: nil, query: nil, started_at: nil}}
  end

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       running?: is_port(state.port),
       query: state.query,
       started_at: state.started_at,
       log: Enum.reverse(state.log)
     }, state}
  end

  @impl true
  def handle_info({port, {:data, {_eol, line}}}, %{port: port} = state) do
    entry = log_entry(line)
    broadcast(:log, entry)
    {:noreply, %{state | log: trim([entry | state.log])}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    entry = log_entry("[runner] session exited (status=#{status})")
    broadcast(:exited, %{status: status})
    {:noreply, %{state | port: nil, os_pid: nil, log: trim([entry | state.log])}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Helpers ─────────────────────────────────────────────────────────────────

  # Default: real claude CLI. Tests can override by setting
  #   config :linkbot, Linkbot.SessionRunner, command: {bin, args} | {:fun, fun/1}
  defp build_command(query) do
    case Application.get_env(:linkbot, __MODULE__, [])[:command] do
      {:fun, fun} when is_function(fun, 1) ->
        fun.(query)

      {bin, args} when is_binary(bin) and is_list(args) ->
        {bin, args}

      nil ->
        conn = repo_conn()
        prompt = SessionPrompt.render(query, conn)
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
end
