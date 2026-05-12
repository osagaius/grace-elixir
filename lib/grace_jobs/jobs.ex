defmodule GraceJobs.Jobs do
  @moduledoc """
  Context module: persistence + queries + PubSub for job postings.
  """
  import Ecto.Query
  alias GraceJobs.Repo
  alias GraceJobs.Jobs.Job

  @topic "jobs"

  @doc "Subscribe to live job updates (`{:job_inserted, %Job{}}`)."
  def subscribe do
    Phoenix.PubSub.subscribe(GraceJobs.PubSub, @topic)
  end

  @doc """
  Insert or update a job by `(source, external_id)`. On insert, broadcast.
  Returns `{:ok, %Job{}}` or `{:error, changeset}`.
  """
  def upsert_job(attrs) do
    changeset = Job.changeset(%Job{}, attrs)

    with {:ok, attrs} <- Ecto.Changeset.apply_action(changeset, :insert) do
      conflict_fields = [
        :title,
        :company,
        :url,
        :description,
        :location,
        :remote,
        :tags,
        :role,
        :seniority,
        :posted_at,
        :raw,
        :updated_at
      ]

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs_map =
        attrs
        |> Map.from_struct()
        |> Map.drop([:__meta__, :id, :inserted_at])
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)

      case Repo.insert_all(Job, [attrs_map],
             on_conflict: {:replace, conflict_fields},
             conflict_target: [:source, :external_id],
             returning: true
           ) do
        {1, [job]} ->
          broadcast({:job_upserted, job})
          {:ok, job}

        other ->
          {:error, other}
      end
    end
  end

  @doc "List today's jobs, newest first. Optional :role / :tag / :source filters."
  def list_today(filters \\ []) do
    today_start =
      DateTime.utc_now()
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00])

    Job
    |> where([j], j.inserted_at >= ^today_start)
    |> apply_filters(filters)
    |> order_by([j], desc: j.posted_at, desc: j.inserted_at)
    |> Repo.all()
  end

  @doc "List jobs across all dates with filters; useful for the LiveView."
  def list_jobs(filters \\ []) do
    Job
    |> apply_filters(filters)
    |> order_by([j], desc: j.posted_at, desc: j.inserted_at)
    |> limit(^Keyword.get(filters, :limit, 200))
    |> Repo.all()
  end

  def count_today do
    today_start =
      DateTime.utc_now()
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00])

    Job
    |> where([j], j.inserted_at >= ^today_start)
    |> select([j], count(j.id))
    |> Repo.one()
  end

  def count_total do
    Repo.one(from j in Job, select: count(j.id))
  end

  def get_job!(id), do: Repo.get!(Job, id)

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:role, nil}, q -> q
      {:role, role}, q -> where(q, [j], j.role == ^role)
      {:source, nil}, q -> q
      {:source, src}, q -> where(q, [j], j.source == ^src)
      {:tag, nil}, q -> q
      {:tag, tag}, q -> where(q, [j], ^tag in j.tags)
      {:remote_only, true}, q -> where(q, [j], j.remote == true)
      {:applied_only, true}, q -> where(q, [j], j.status == "applied")
      _, q -> q
    end)
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(GraceJobs.PubSub, @topic, message)
  end
end
