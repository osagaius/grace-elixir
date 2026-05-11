defmodule LinkbotWeb.JobsLive do
  use LinkbotWeb, :live_view

  alias Linkbot.{Jobs, SessionRunner, SessionPrompt}

  @poll_interval_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Jobs.subscribe()
      SessionRunner.subscribe()
      :timer.send_interval(@poll_interval_ms, self(), :refresh_jobs)
    end

    %{running?: running?, query: query, log: log} = SessionRunner.status()

    {:ok,
     socket
     |> assign(:page_title, "Linkbot")
     |> assign(:default_query, SessionPrompt.default_query())
     |> assign(:running?, running?)
     |> assign(:current_query, query)
     |> assign(:log_count, length(log))
     |> stream(:log, Enum.map(log, &with_id/1))
     |> assign_jobs()}
  end

  defp assign_jobs(socket) do
    jobs = Jobs.list_jobs()
    counts = Jobs.count_by_status()
    assign(socket, jobs: jobs, counts: counts, total: length(jobs))
  end

  # ── Events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("run", _params, socket) do
    case SessionRunner.run() do
      {:ok, _pid} -> {:noreply, put_flash(socket, :info, "Session started")}
      {:error, :already_running} -> {:noreply, put_flash(socket, :error, "Already running")}
    end
  end

  def handle_event("stop", _params, socket) do
    SessionRunner.stop_session()
    {:noreply, put_flash(socket, :info, "Session stopped")}
  end

  def handle_event("clear_log", _params, socket) do
    {:noreply,
     socket
     |> stream(:log, [], reset: true)
     |> assign(:log_count, 0)}
  end

  # ── PubSub ────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:started, %{query: query}}, socket) do
    {:noreply, assign(socket, running?: true, current_query: query)}
  end

  def handle_info({:exited, %{status: status}}, socket) do
    entry = log_entry("[runner] exit status #{status}")

    {:noreply,
     socket
     |> assign(:running?, false)
     |> push_log(entry)}
  end

  def handle_info({:stopped, _}, socket), do: {:noreply, assign(socket, :running?, false)}

  def handle_info({:log, entry}, socket), do: {:noreply, push_log(socket, entry)}

  def handle_info({event, _}, socket) when event in [:job_created, :job_updated, :job_deleted],
    do: {:noreply, assign_jobs(socket)}

  def handle_info(:refresh_jobs, socket), do: {:noreply, assign_jobs(socket)}

  defp push_log(socket, entry) do
    socket
    |> stream_insert(:log, with_id(entry), at: 0)
    |> update(:log_count, &(&1 + 1))
  end

  defp log_entry(line), do: %{at: DateTime.utc_now(), line: line}

  defp with_id(%{at: at} = entry) do
    id =
      Map.get_lazy(entry, :id, fn ->
        "log-#{System.unique_integer([:monotonic, :positive])}-#{DateTime.to_unix(at, :microsecond)}"
      end)

    Map.put(entry, :id, id)
  end

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 text-base-content">
      <div class="max-w-7xl mx-auto p-6 space-y-6">
        <header class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold tracking-tight">Linkbot</h1>
            <p class="text-sm opacity-70">
              Phoenix LiveView dashboard for a Claude session that applies to LinkedIn jobs.
            </p>
          </div>
          <div class="flex gap-2">
            <button :if={!@running?} phx-click="run" class="btn btn-primary">
              ▶ Run session
            </button>
            <button :if={@running?} phx-click="stop" class="btn btn-error">
              ■ Stop session
            </button>
          </div>
        </header>

        <section class="card bg-base-100 shadow">
          <div class="card-body">
            <div class="flex flex-wrap gap-6 items-center">
              <div>
                <div class="text-xs uppercase opacity-60">Status</div>
                <div class="font-mono">
                  <span :if={@running?} class="text-success">● running</span>
                  <span :if={!@running?} class="opacity-60">○ idle</span>
                </div>
              </div>
              <div class="flex-1">
                <div class="text-xs uppercase opacity-60">Search query</div>
                <div class="font-mono text-sm">{@current_query || @default_query}</div>
              </div>
              <div class="flex gap-4">
                <.stat label="total" value={@total} />
                <.stat label="found" value={Map.get(@counts, "found", 0)} />
                <.stat label="applied" value={Map.get(@counts, "applied", 0)} />
                <.stat label="skipped" value={Map.get(@counts, "skipped", 0)} />
                <.stat label="failed" value={Map.get(@counts, "failed", 0)} />
              </div>
            </div>
          </div>
        </section>

        <section class="card bg-base-100 shadow">
          <div class="card-body p-0">
            <div class="overflow-x-auto">
              <table class="table table-zebra">
                <thead>
                  <tr>
                    <th>Title</th>
                    <th>Company</th>
                    <th>Location</th>
                    <th>Status</th>
                    <th>Applied at</th>
                    <th>Notes</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@jobs == []}>
                    <td colspan="7" class="text-center opacity-60 py-10">
                      No jobs yet — click <span class="font-semibold">Run session</span>.
                    </td>
                  </tr>
                  <tr :for={job <- @jobs}>
                    <td class="font-medium">{job.title}</td>
                    <td>{job.company}</td>
                    <td class="opacity-70">{job.location}</td>
                    <td><.status_badge status={job.status} /></td>
                    <td class="font-mono text-xs">{format_dt(job.applied_at)}</td>
                    <td class="opacity-70 max-w-md truncate">{job.notes}</td>
                    <td>
                      <a
                        :if={job.url}
                        href={job.url}
                        target="_blank"
                        class="link link-primary text-sm"
                      >
                        open ↗
                      </a>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <section class="card bg-base-100 shadow">
          <div class="card-body">
            <div class="flex justify-between items-center">
              <h2 class="card-title">Session log</h2>
              <button phx-click="clear_log" class="btn btn-ghost btn-xs">clear</button>
            </div>
            <div
              id="log"
              phx-update="stream"
              class="bg-neutral text-neutral-content font-mono text-xs rounded p-3 h-64 overflow-y-auto flex flex-col-reverse"
            >
              <div
                :for={{dom_id, entry} <- @streams.log}
                id={dom_id}
                class="whitespace-pre-wrap"
              >
                <span class="opacity-60">{format_time(entry.at)}</span> {entry.line}
              </div>
            </div>
            <div :if={@log_count == 0} class="text-xs opacity-60 mt-1">
              — waiting for output —
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp stat(assigns) do
    ~H"""
    <div class="text-center">
      <div class="text-xs uppercase opacity-60">{@label}</div>
      <div class="text-lg font-mono">{@value}</div>
    </div>
    """
  end

  attr :status, :string, default: nil

  defp status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm", badge_class(@status)]}>{@status || "—"}</span>
    """
  end

  defp badge_class("applied"), do: "badge-success"
  defp badge_class("applying"), do: "badge-warning"
  defp badge_class("found"), do: "badge-info"
  defp badge_class("skipped"), do: "badge-ghost"
  defp badge_class("failed"), do: "badge-error"
  defp badge_class(_), do: "badge-ghost"

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_time(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
end
