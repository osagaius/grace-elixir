defmodule GraceJobs.Workers.DailyHarvestWorkerTest do
  use GraceJobs.DataCase, async: false
  use Oban.Testing, repo: GraceJobs.Repo
  import Mox

  alias GraceJobs.Workers.DailyHarvestWorker

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    # Start an isolated pipeline supervisor and stub the mocks so the
    # tasks the worker enqueues drain cleanly within this test.
    Mox.set_mox_global()
    stub(GraceJobs.ScraperMock, :fetch, fn _ -> {:ok, []} end)
    stub(GraceJobs.LLMMock, :classify, fn _ -> {:ok, %{role: nil, seniority: nil, tags: []}} end)
    start_supervised!(GraceJobs.Pipeline.Supervisor)
    :ok
  end

  test "perform/1 succeeds with default sources" do
    assert :ok = perform_job(DailyHarvestWorker, %{})
  end

  test "perform/1 honours explicit sources arg" do
    args = %{"sources" => [["remoteok", %{}]]}
    assert :ok = perform_job(DailyHarvestWorker, args)
  end
end
