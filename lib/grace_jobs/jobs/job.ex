defmodule GraceJobs.Jobs.Job do
  @moduledoc """
  A scraped, normalised, and (optionally) LLM-classified job posting.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @sources ~w(remoteok weworkremotely hackernews)
  @roles ~w(typescript javascript python kubernetes devops sre rust go java elixir other)
  @seniorities ~w(intern junior mid senior staff principal lead)

  @type t :: %__MODULE__{}

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
    field :posted_at, :utc_datetime
    field :raw, :map, default: %{}

    field :status, :string, default: "found"
    field :applied_at, :naive_datetime

    timestamps(type: :utc_datetime)
  end

  @required ~w(source external_id title url)a
  @optional ~w(company description location remote tags role seniority posted_at raw)a

  def changeset(job, attrs) do
    job
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:role, @roles ++ [nil])
    |> validate_inclusion(:seniority, @seniorities ++ [nil])
    |> validate_length(:title, max: 500)
    |> validate_length(:url, max: 2000)
    |> unique_constraint([:source, :external_id], name: :jobs_source_external_id_index)
  end

  def sources, do: @sources
  def roles, do: @roles
  def seniorities, do: @seniorities
end
