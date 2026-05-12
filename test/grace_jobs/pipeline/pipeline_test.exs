defmodule GraceJobs.PipelineTest do
  @moduledoc """
  End-to-end test of the GenStage pipeline using Mox stubs for both
  the scrapers and the LLM. Verifies that scrape tasks pushed into the
  producer end up as persisted, classified jobs.
  """
  use GraceJobs.DataCase, async: false
  import Mox

  alias GraceJobs.Jobs
  alias GraceJobs.Pipeline.SourceProducer
  alias GraceJobs.Factory

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    parent = self()

    Mox.set_mox_global()

    GraceJobs.ScraperMock
    |> stub(:fetch, fn opts ->
      send(parent, {:fetch_called, opts})
      {:ok, [Factory.raw_job_attrs(%{external_id: "pipe-1", title: "TS Eng"})]}
    end)

    GraceJobs.LLMMock
    |> stub(:classify, fn _raw ->
      {:ok, %{role: "typescript", seniority: "senior", tags: ["typescript", "react"]}}
    end)

    # Pipeline supervisor is opt-in for tests; start under the test
    # supervisor so it terminates with the test.
    start_supervised!(GraceJobs.Pipeline.Supervisor)
    Jobs.subscribe()
    :ok
  end

  test "scrape task → DB → broadcast" do
    SourceProducer.enqueue({:remoteok, []})

    assert_receive {:job_upserted, job}, 2_000
    assert job.title == "TS Eng"
    assert job.role == "typescript"
    assert "typescript" in job.tags
    assert job.source == "remoteok"
  end

  test "many tasks deduplicate by (source, external_id)" do
    SourceProducer.enqueue_many([{:remoteok, []}, {:remoteok, []}])
    assert_receive {:job_upserted, _}, 2_000
    Process.sleep(200)
    assert length(Jobs.list_jobs()) == 1
  end
end
