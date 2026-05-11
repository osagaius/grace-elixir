defmodule Linkbot.JobsTest do
  use Linkbot.DataCase

  alias Linkbot.Jobs
  alias Linkbot.Jobs.Job

  import Linkbot.JobsFixtures

  @invalid_attrs %{source: nil, external_id: nil, title: nil, url: nil}

  test "list_jobs/0 returns all jobs" do
    job = job_fixture()
    assert Jobs.list_jobs() == [job]
  end

  test "get_job!/1 returns the job with given id" do
    job = job_fixture()
    assert Jobs.get_job!(job.id) == job
  end

  test "create_job/1 with valid data creates a job" do
    attrs = %{
      source: "linkedin",
      external_id: "abc-123",
      title: "Backend Engineer",
      company: "Acme",
      url: "https://www.linkedin.com/jobs/view/abc-123",
      location: "Remote",
      status: "found"
    }

    assert {:ok, %Job{} = job} = Jobs.create_job(attrs)
    assert job.source == "linkedin"
    assert job.external_id == "abc-123"
    assert job.title == "Backend Engineer"
    assert job.status == "found"
  end

  test "create_job/1 with invalid data returns error changeset" do
    assert {:error, %Ecto.Changeset{}} = Jobs.create_job(@invalid_attrs)
  end

  test "create_job/1 enforces (source, external_id) uniqueness" do
    {:ok, _} = Jobs.create_job(%{source: "linkedin", external_id: "dup", title: "A", url: "u1"})
    {:error, changeset} = Jobs.create_job(%{source: "linkedin", external_id: "dup", title: "B", url: "u2"})
    # Ecto attaches the composite-key unique error to the first column listed.
    assert "has already been taken" in errors_on(changeset).source
  end

  test "update_job/2 transitions status to applied" do
    job = job_fixture()
    assert {:ok, %Job{status: "applied"} = updated} =
             Jobs.update_job(job, %{status: "applied", applied_at: ~N[2026-05-08 12:00:00]})

    assert updated.applied_at == ~N[2026-05-08 12:00:00]
  end

  test "delete_job/1 deletes the job" do
    job = job_fixture()
    assert {:ok, %Job{}} = Jobs.delete_job(job)
    assert_raise Ecto.NoResultsError, fn -> Jobs.get_job!(job.id) end
  end

  test "change_job/1 returns a job changeset" do
    job = job_fixture()
    assert %Ecto.Changeset{} = Jobs.change_job(job)
  end
end
