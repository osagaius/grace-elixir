defmodule GraceJobs.JobsTest do
  use GraceJobs.DataCase, async: false

  alias GraceJobs.Jobs
  import GraceJobs.Factory

  describe "upsert_job/1" do
    test "inserts a valid job and broadcasts" do
      Jobs.subscribe()
      attrs = raw_job_attrs()

      assert {:ok, job} = Jobs.upsert_job(attrs)
      assert job.title == attrs.title
      assert job.role == nil
      assert_received {:job_upserted, ^job}
    end

    test "rejects invalid attrs" do
      assert {:error, %Ecto.Changeset{}} =
               Jobs.upsert_job(%{source: "bogus", external_id: "1", title: "x", url: "y"})
    end

    test "upsert is idempotent on (source, external_id)" do
      attrs = raw_job_attrs(%{external_id: "stable-1", title: "First"})
      assert {:ok, _} = Jobs.upsert_job(attrs)
      assert {:ok, updated} = Jobs.upsert_job(%{attrs | title: "Second"})
      assert updated.title == "Second"
      assert Jobs.list_jobs() |> length() == 1
    end
  end

  describe "list_jobs/1 filters" do
    setup do
      insert(:job, role: "typescript", source: "remoteok", tags: ["typescript", "react"])
      insert(:job, role: "python", source: "weworkremotely", tags: ["python", "django"])
      insert(:job, role: "kubernetes", source: "hackernews", tags: ["k8s", "go"])
      :ok
    end

    test "filters by role" do
      assert [j] = Jobs.list_jobs(role: "python")
      assert j.role == "python"
    end

    test "filters by source" do
      assert [j] = Jobs.list_jobs(source: "hackernews")
      assert j.source == "hackernews"
    end

    test "filters by tag" do
      assert [j] = Jobs.list_jobs(tag: "django")
      assert "django" in j.tags
    end
  end

  test "count_today reflects today's jobs" do
    assert Jobs.count_today() == 0
    insert(:job)
    assert Jobs.count_today() == 1
  end
end
