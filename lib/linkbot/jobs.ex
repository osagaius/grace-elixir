defmodule Linkbot.Jobs do
  @moduledoc """
  Context for the central `jobs` table (shared with the grace_jobs project).
  Linkbot's Claude session writes to it via `psql` and reads it from Phoenix
  via Ecto.
  """

  import Ecto.Query, warn: false
  alias Linkbot.Repo
  alias Linkbot.Jobs.Job

  @topic "jobs"

  def subscribe, do: Phoenix.PubSub.subscribe(Linkbot.PubSub, @topic)

  defp broadcast(event, payload),
    do: Phoenix.PubSub.broadcast(Linkbot.PubSub, @topic, {event, payload})

  def list_jobs(filters \\ []) do
    Job
    |> apply_filters(filters)
    |> order_by([j], desc: j.inserted_at)
    |> Repo.all()
  end

  def get_job!(id), do: Repo.get!(Job, id)

  def create_job(attrs) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
    |> tap_broadcast(:job_created)
  end

  def update_job(%Job{} = job, attrs) do
    job
    |> Job.changeset(attrs)
    |> Repo.update()
    |> tap_broadcast(:job_updated)
  end

  def delete_job(%Job{} = job) do
    job
    |> Repo.delete()
    |> tap_broadcast(:job_deleted)
  end

  def change_job(%Job{} = job, attrs \\ %{}), do: Job.changeset(job, attrs)

  def count_by_status do
    Repo.all(from j in Job, group_by: j.status, select: {j.status, count(j.id)})
    |> Enum.into(%{})
  end

  def filter_options do
    %{
      roles: distinct_values(:role),
      sources: distinct_values(:source)
    }
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:role, nil}, q -> q
      {:role, role}, q -> where(q, [j], j.role == ^role)
      {:source, nil}, q -> q
      {:source, source}, q -> where(q, [j], j.source == ^source)
      {:tag, nil}, q -> q
      {:tag, tag}, q -> where(q, [j], ^tag in j.tags)
      {:remote_only, true}, q -> where(q, [j], j.remote == true)
      {:remote_only, _}, q -> q
      {:applied_only, true}, q -> where(q, [j], j.status == "applied")
      {:applied_only, _}, q -> q
      {:location, nil}, q -> q
      {:location, ""}, q -> q
      {:location, location}, q -> where(q, [j], ilike(j.location, ^"%#{location}%"))
      _, q -> q
    end)
  end

  defp distinct_values(field) when field in [:role, :source] do
    Repo.all(
      from j in Job, distinct: true, order_by: [asc: field(j, ^field)], select: field(j, ^field)
    )
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp tap_broadcast({:ok, job} = result, event) do
    broadcast(event, job)
    result
  end

  defp tap_broadcast(other, _event), do: other
end
