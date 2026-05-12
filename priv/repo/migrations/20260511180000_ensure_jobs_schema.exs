defmodule Linkbot.Repo.Migrations.EnsureJobsSchema do
  use Ecto.Migration

  # Idempotent: this migration is safe to run against `grace_jobs_dev` (where
  # the base table already exists, owned by another project) and against a
  # fresh `linkbot_test` database (where everything needs to be created).
  # Linkbot only owns the application-tracking columns at the bottom.

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS jobs (
      id BIGSERIAL PRIMARY KEY,
      source VARCHAR(255) NOT NULL,
      external_id VARCHAR(255) NOT NULL,
      title VARCHAR(255) NOT NULL,
      company VARCHAR(255),
      url VARCHAR(255) NOT NULL,
      description TEXT,
      location VARCHAR(255),
      remote BOOLEAN NOT NULL DEFAULT FALSE,
      tags VARCHAR(255)[] NOT NULL DEFAULT ARRAY[]::VARCHAR[],
      role VARCHAR(255),
      seniority VARCHAR(255),
      posted_at TIMESTAMP(0) WITHOUT TIME ZONE,
      raw JSONB NOT NULL DEFAULT '{}'::jsonb,
      inserted_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL,
      updated_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL
    );
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS jobs_source_external_id_index ON jobs (source, external_id);"
    )

    execute("CREATE INDEX IF NOT EXISTS jobs_posted_at_index ON jobs (posted_at);")
    execute("CREATE INDEX IF NOT EXISTS jobs_role_index ON jobs (role);")
    execute("CREATE INDEX IF NOT EXISTS jobs_tags_index ON jobs USING gin (tags);")

    # Linkbot application-tracking columns
    execute(
      "ALTER TABLE jobs ADD COLUMN IF NOT EXISTS status VARCHAR(255) NOT NULL DEFAULT 'found';"
    )

    execute(
      "ALTER TABLE jobs ADD COLUMN IF NOT EXISTS applied_at TIMESTAMP(0) WITHOUT TIME ZONE;"
    )

    execute("ALTER TABLE jobs ADD COLUMN IF NOT EXISTS notes TEXT;")
    execute("CREATE INDEX IF NOT EXISTS jobs_status_index ON jobs (status);")
  end

  def down do
    execute("DROP INDEX IF EXISTS jobs_status_index;")
    execute("ALTER TABLE jobs DROP COLUMN IF EXISTS notes;")
    execute("ALTER TABLE jobs DROP COLUMN IF EXISTS applied_at;")
    execute("ALTER TABLE jobs DROP COLUMN IF EXISTS status;")
  end
end
