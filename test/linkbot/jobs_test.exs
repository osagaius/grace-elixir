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

  test "list_jobs/1 can return only applied jobs" do
    applied = job_fixture(%{status: "applied", external_id: "applied-job"})
    _found = job_fixture(%{status: "found", external_id: "found-job"})

    assert Jobs.list_jobs(applied_only: true) == [applied]
  end

  test "list_jobs/1 can filter by role" do
    backend = job_fixture(%{external_id: "backend-job", role: "backend"})
    _frontend = job_fixture(%{external_id: "frontend-job", role: "frontend"})

    assert Jobs.list_jobs(role: "backend") == [backend]
  end

  test "list_jobs/1 can filter by source" do
    linkedin = job_fixture(%{external_id: "linkedin-job", source: "linkedin"})
    _remoteok = job_fixture(%{external_id: "remoteok-job", source: "remoteok"})

    assert Jobs.list_jobs(source: "linkedin") == [linkedin]
  end

  test "list_jobs/1 can filter by tag" do
    tagged = job_fixture(%{external_id: "tagged-job", tags: ["elixir", "phoenix"]})
    _untagged = job_fixture(%{external_id: "untagged-job", tags: ["python"]})

    assert Jobs.list_jobs(tag: "phoenix") == [tagged]
  end

  test "list_jobs/1 can filter by location" do
    remote = job_fixture(%{external_id: "remote-job", location: "Remote - United States"})
    _onsite = job_fixture(%{external_id: "onsite-job", location: "Dublin, Ireland"})

    assert Jobs.list_jobs(location: "united states") == [remote]
  end

  test "list_jobs/1 can filter by remote jobs" do
    remote = job_fixture(%{external_id: "remote-only-job", remote: true})
    _onsite = job_fixture(%{external_id: "onsite-only-job", remote: false})

    assert Jobs.list_jobs(remote_only: true) == [remote]
  end

  test "filter_options/0 returns distinct roles and sources" do
    job_fixture(%{external_id: "backend-linkedin", role: "backend", source: "linkedin"})
    job_fixture(%{external_id: "backend-remoteok", role: "backend", source: "remoteok"})

    assert %{roles: ["backend"], sources: ["linkedin", "remoteok"]} = Jobs.filter_options()
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

    {:error, changeset} =
      Jobs.create_job(%{source: "linkedin", external_id: "dup", title: "B", url: "u2"})

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
