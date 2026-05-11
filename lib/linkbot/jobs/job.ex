defmodule Linkbot.Jobs.Job do
  @moduledoc """
  Shared central `jobs` table. The base columns (source, external_id, url,
  tags, raw, etc.) are owned by the upstream `grace_jobs` schema; Linkbot
  adds the application-tracking columns (status, applied_at, notes).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @cast_fields ~w(
    source external_id title company url description location remote
    tags role seniority posted_at raw status applied_at notes
  )a

  @required_fields ~w(source external_id title url)a

  schema "jobs" do
    field :source, :string
    field :external_id, :string
    field :title, :string
    field :company, :string
    field :url, :string
    field :description, :string
    field :location, :string
    field :remote, :boolean, default: false
    field :tags, {:array, :string}, default: []
    field :role, :string
    field :seniority, :string
    field :posted_at, :naive_datetime
    field :raw, :map, default: %{}

    # Linkbot application tracking
    field :status, :string, default: "found"
    field :applied_at, :naive_datetime
    field :notes, :string

    timestamps(type: :naive_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:source, :external_id], name: :jobs_source_external_id_index)
  end
end
