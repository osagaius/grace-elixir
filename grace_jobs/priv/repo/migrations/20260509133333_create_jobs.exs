defmodule GraceJobs.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    create table(:jobs) do
      add :source, :string, null: false
      add :external_id, :string, null: false
      add :title, :string, null: false
      add :company, :string
      add :url, :string, null: false
      add :description, :text
      add :location, :string
      add :remote, :boolean, default: false, null: false
      add :tags, {:array, :string}, default: [], null: false
      add :role, :string
      add :seniority, :string
      add :posted_at, :utc_datetime
      add :raw, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:jobs, [:source, :external_id])
    create index(:jobs, [:role])
    create index(:jobs, [:posted_at])
    create index(:jobs, [:tags], using: "GIN")
  end
end
