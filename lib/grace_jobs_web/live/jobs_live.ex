defmodule GraceJobsWeb.JobsLive do
  @moduledoc """
  Live dashboard of recently harvested job postings. Updates in
  real-time as the GenStage pipeline persists new jobs.
  """
  use GraceJobsWeb, :live_view

  alias GraceJobs.Jobs
  alias GraceJobs.Jobs.Job

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Jobs.subscribe()

    {:ok,
     socket
     |> assign(:role, nil)
     |> assign(:source, nil)
     |> assign(:tag, nil)
     |> assign(:remote_only, false)
     |> assign(:applied_only, false)
     |> assign(:roles, Job.roles())
     |> assign(:sources, Job.sources())
     |> load_jobs()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:role, params["role"])
     |> assign(:source, params["source"])
     |> assign(:tag, params["tag"])
     |> assign(:remote_only, params["remote_only"] == "true")
     |> assign(:applied_only, params["applied_only"] == "true")
     |> load_jobs()}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/?#{[role: filter["role"], source: filter["source"], tag: filter["tag"], remote_only: filter["remote_only"] == "true", applied_only: filter["applied_only"] == "true"]}"
     )}
  end

  def handle_event("clear", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:job_upserted, _job}, socket) do
    {:noreply, load_jobs(socket)}
  end

  defp load_jobs(socket) do
    filters = [
      role: nilify(socket.assigns.role),
      source: nilify(socket.assigns.source),
      tag: nilify(socket.assigns.tag),
      remote_only: socket.assigns.remote_only,
      applied_only: socket.assigns.applied_only,
      limit: 200
    ]

    socket
    |> assign(:jobs, Jobs.list_jobs(filters))
    |> assign(:today_count, Jobs.count_today())
    |> assign(:total_count, Jobs.count_total())
  end

  defp nilify(""), do: nil
  defp nilify(v), do: v

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl px-4 py-6">
      <header class="flex items-baseline justify-between mb-6">
        <div>
          <h1 class="text-2xl font-semibold">Grace — daily software jobs</h1>
          <p class="text-sm opacity-70" id="today-count">
            <span class="font-mono">{@total_count}</span> jobs in database
            · <span class="font-mono">{@today_count}</span> added today.
          </p>
        </div>
        <button
          type="button"
          phx-click="clear"
          class="text-sm underline opacity-70 hover:opacity-100"
        >
          Clear filters
        </button>
      </header>

      <.form
        for={%{}}
        as={:filter}
        phx-change="filter"
        class="grid grid-cols-2 sm:grid-cols-5 gap-3 mb-6"
        id="job-filters"
      >
        <select name="filter[role]" class="select select-bordered">
          <option value="">All roles</option>
          <option :for={r <- @roles} value={r} selected={@role == r}>{r}</option>
        </select>
        <select name="filter[source]" class="select select-bordered">
          <option value="">All sources</option>
          <option :for={s <- @sources} value={s} selected={@source == s}>{s}</option>
        </select>
        <input
          type="text"
          name="filter[tag]"
          placeholder="tag (e.g. typescript)"
          value={@tag || ""}
          class="input input-bordered"
        />
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="filter[remote_only]"
            value="true"
            checked={@remote_only}
            class="checkbox"
          /> remote only
        </label>
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="filter[applied_only]"
            value="true"
            checked={@applied_only}
            class="checkbox"
          /> applied only
        </label>
      </.form>

      <ul id="jobs" phx-update="replace" class="divide-y divide-base-300 border rounded">
        <li :for={job <- @jobs} id={"job-#{job.id}"} class="p-3 hover:bg-base-200">
          <div class="flex items-baseline justify-between gap-4">
            <div class="min-w-0">
              <a href={job.url} target="_blank" rel="noopener" class="font-medium hover:underline">
                {job.title}
              </a>
              <div class="text-sm opacity-80 truncate">
                {job.company || "—"} · {job.source}
                <span :if={job.role} class="badge badge-sm ml-1">{job.role}</span>
                <span :if={job.seniority} class="badge badge-sm badge-outline ml-1">
                  {job.seniority}
                </span>
              </div>
            </div>
            <div class="flex items-center gap-3 whitespace-nowrap">
              <span class="text-xs opacity-60">
                {format_dt(job.posted_at || job.inserted_at)}
              </span>
              <a
                href={job.url}
                target="_blank"
                rel="noopener"
                class="btn btn-xs btn-primary"
                aria-label={"Open #{job.title} in a new tab"}
              >
                Open ↗
              </a>
            </div>
          </div>
          <div :if={job.tags != []} class="mt-1 flex flex-wrap gap-1">
            <span :for={tag <- Enum.take(job.tags, 8)} class="badge badge-ghost badge-sm">
              {tag}
            </span>
          </div>
        </li>
        <li :if={@jobs == []} class="p-6 text-center opacity-60">
          No jobs match your filters yet.
        </li>
      </ul>
    </div>
    """
  end

  defp format_dt(nil), do: ""

  defp format_dt(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d %H:%M")
  end
end
