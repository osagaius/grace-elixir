defmodule LinkbotWeb.ApplyLive do
  use LinkbotWeb, :live_view

  alias Linkbot.{Jobs, ApplyBot.SessionRunner, ApplyBot.SessionPrompt}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SessionRunner.subscribe()

    %{running?: running?, job_url: job_url, resume_url: resume_url, log: log} =
      SessionRunner.status()

    {:ok,
     socket
     |> assign(:page_title, "ApplyBot")
     |> assign(:default_job_url, SessionPrompt.default_job_url())
     |> assign(:default_resume_url, SessionPrompt.default_resume_url())
     |> assign(:running?, running?)
     |> assign(:current_job_url, job_url)
     |> assign(:current_resume_url, resume_url)
     |> assign(:job, nil)
     |> assign(:job_url, job_url || SessionPrompt.default_job_url())
     |> assign(:resume_url, resume_url || SessionPrompt.default_resume_url())
     |> assign(:log_count, length(log))
     |> stream(:log, Enum.map(log, &with_id/1))
     |> assign(:form, build_form(SessionPrompt.default_job_url(), SessionPrompt.default_resume_url()))}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case load_job(id) do
      {:ok, job} ->
        {:noreply,
         socket
         |> assign(:job, job)
         |> assign(:page_title, "ApplyBot — #{job.title || "job ##{job.id}"}")
         |> assign(:job_url, job.url)
         |> assign(:form, build_form(job.url, socket.assigns.resume_url))}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Job not found")
         |> push_navigate(to: ~p"/apply")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp load_job(id) do
    case Integer.parse(id) do
      {int_id, ""} ->
        try do
          {:ok, Jobs.get_job!(int_id)}
        rescue
          Ecto.NoResultsError -> :error
        end

      _ ->
        :error
    end
  end

  # ── Events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("update_form", %{"apply" => %{"job_url" => j, "resume_url" => r}}, socket) do
    {:noreply,
     socket
     |> assign(:job_url, j)
     |> assign(:resume_url, r)
     |> assign(:form, build_form(j, r))}
  end

  def handle_event("run", _params, socket) do
    job_url = String.trim(socket.assigns.job_url || "")
    resume_url = String.trim(socket.assigns.resume_url || "")

    cond do
      job_url == "" ->
        {:noreply, put_flash(socket, :error, "Job URL is required")}

      resume_url == "" ->
        {:noreply, put_flash(socket, :error, "Resume URL is required")}

      true ->
        case SessionRunner.run(job_url, resume_url) do
          {:ok, _pid} ->
            {:noreply, put_flash(socket, :info, "Apply session started")}

          {:error, :already_running} ->
            {:noreply, put_flash(socket, :error, "Already running")}
        end
    end
  end

  def handle_event("stop", _params, socket) do
    SessionRunner.stop_session()
    {:noreply, put_flash(socket, :info, "Apply session stopped")}
  end

  def handle_event("clear_log", _params, socket) do
    {:noreply,
     socket
     |> stream(:log, [], reset: true)
     |> assign(:log_count, 0)}
  end

  # ── PubSub ────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:started, %{job_url: j, resume_url: r}}, socket) do
    {:noreply,
     socket
     |> assign(:running?, true)
     |> assign(:current_job_url, j)
     |> assign(:current_resume_url, r)}
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

  def handle_info(_other, socket), do: {:noreply, socket}

  defp push_log(socket, entry) do
    socket
    |> stream_insert(:log, with_id(entry), at: 0)
    |> update(:log_count, &(&1 + 1))
  end

  defp log_entry(line), do: %{at: DateTime.utc_now(), line: line}

  defp with_id(%{at: at} = entry) do
    id =
      Map.get_lazy(entry, :id, fn ->
        "applylog-#{System.unique_integer([:monotonic, :positive])}-#{DateTime.to_unix(at, :microsecond)}"
      end)

    Map.put(entry, :id, id)
  end

  defp build_form(job_url, resume_url) do
    to_form(%{"job_url" => job_url, "resume_url" => resume_url}, as: :apply)
  end

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto p-6 space-y-6">
        <header class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold tracking-tight">ApplyBot</h1>
            <p :if={!@job} class="text-sm opacity-70">
              Phoenix LiveView dashboard for a Claude session that applies to a single job using your resume.
            </p>
            <p :if={@job} class="text-sm opacity-70">
              Applying to
              <span class="font-medium">{@job.title}</span>
              <span :if={@job.company}>@ <span class="font-medium">{@job.company}</span></span>
              <span class="opacity-50">— job ##{@job.id}</span>
            </p>
          </div>
          <div class="flex gap-2">
            <.link navigate={~p"/"} class="btn btn-ghost btn-sm">← jobs</.link>
            <button :if={!@running?} phx-click="run" class="btn btn-primary">
              ▶ Apply
            </button>
            <button :if={@running?} phx-click="stop" class="btn btn-error">
              ■ Stop
            </button>
          </div>
        </header>

        <section class="card bg-base-100 shadow">
          <div class="card-body">
            <.form
              for={@form}
              id="apply-form"
              phx-change="update_form"
              class="space-y-3"
            >
              <.input
                field={@form[:job_url]}
                type="text"
                label="Job application URL"
                placeholder="https://jobs.ashbyhq.com/.../application"
              />
              <.input
                field={@form[:resume_url]}
                type="text"
                label="Resume URL (Google Drive sharing link is fine)"
                placeholder="https://drive.google.com/file/d/.../view"
              />
            </.form>
          </div>
        </section>

        <section class="card bg-base-100 shadow">
          <div class="card-body">
            <div class="flex flex-wrap gap-6 items-center">
              <div>
                <div class="text-xs uppercase opacity-60">Status</div>
                <div class="font-mono">
                  <span :if={@running?} class="text-success">● applying</span>
                  <span :if={!@running?} class="opacity-60">○ idle</span>
                </div>
              </div>
              <div class="flex-1 min-w-0">
                <div class="text-xs uppercase opacity-60">Current job</div>
                <div class="font-mono text-xs truncate">
                  {@current_job_url || "—"}
                </div>
              </div>
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
              id="apply-log"
              phx-update="stream"
              class="bg-neutral text-neutral-content font-mono text-xs rounded p-3 h-96 overflow-y-auto flex flex-col-reverse"
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
    </Layouts.app>
    """
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_time(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
end
