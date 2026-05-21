defmodule Linkbot.ApplyBot.ApplyWorkerTest do
  # async: false — the worker drives the singleton SessionRunner, and we
  # toggle the runner's `command:` config to stub the bash subprocess.
  use Linkbot.DataCase, async: false
  use Oban.Testing, repo: Linkbot.Repo

  alias Linkbot.ApplyBot.{ApplyWorker, SessionRunner}
  alias Linkbot.Jobs.Job

  @job_url "https://jobs.ashbyhq.com/example/abc-worker-test"
  @resume_url "https://drive.google.com/file/d/RESUMEID/view?usp=sharing"
  @args %{"job_url" => @job_url, "resume_url" => @resume_url}

  setup do
    # Belt-and-braces: tests share the sandbox owner's connection but a
    # leftover in-flight run from a prior failure would still poison the
    # singleton SessionRunner.
    SessionRunner.stop_session()
    sentinel = "/tmp/applybot-test-sentinel-#{System.unique_integer([:positive])}"
    File.rm(sentinel)

    on_exit(fn ->
      SessionRunner.stop_session()
      Application.delete_env(:linkbot, Linkbot.ApplyBot.SessionRunner)
      File.rm(sentinel)
    end)

    {:ok, sentinel: sentinel}
  end

  defp set_fake_command(script) do
    Application.put_env(:linkbot, Linkbot.ApplyBot.SessionRunner,
      command: {"/bin/bash", ["-c", script]}
    )
  end

  defp seed_job(status) do
    %Job{}
    |> Job.changeset(%{
      source: "ashby",
      external_id: "abc-worker-test-#{System.unique_integer([:positive])}",
      title: "Test Role",
      url: @job_url,
      status: status
    })
    |> Repo.insert!()
  end

  describe "perform/1" do
    test "happy path: session exits 0 and row is applied → :ok" do
      seed_job("found")
      SessionRunner.subscribe()

      # Stub stalls briefly so the test process has a window to flip the
      # row to 'applied' (simulating what the prompt's STEP 6 does via
      # psql in a real run) before bash exits and the worker re-checks.
      set_fake_command("""
      echo '[step] 1/6 download'
      sleep 0.3
      echo '[step] 6/6 verify'
      """)

      task = Task.async(fn -> perform_job(ApplyWorker, @args) end)

      assert_receive {:started, _}, 1_500
      from(j in Job, where: j.url == ^@job_url) |> Repo.update_all(set: [status: "applied"])

      assert :ok = Task.await(task, 5_000)
      assert Repo.get_by(Job, url: @job_url).status == "applied"
    end

    test "session exits 0 but row was never marked applied → error" do
      seed_job("found")
      set_fake_command("echo 'no-op'")

      assert {:error, :session_exited_without_applied_status} =
               perform_job(ApplyWorker, @args)
    end

    test "non-zero exit propagates as {:error, {:claude_exit, status}}" do
      seed_job("found")
      set_fake_command("echo 'boom' ; exit 7")

      assert {:error, {:claude_exit, 7}} = perform_job(ApplyWorker, @args)
    end

    test "already-applied row short-circuits without invoking the runner", %{
      sentinel: sentinel
    } do
      seed_job("applied")
      set_fake_command("touch #{sentinel} ; exit 0")

      assert :ok = perform_job(ApplyWorker, @args)
      refute File.exists?(sentinel), "SessionRunner was invoked despite already-applied row"
    end

    test "exit 0 with jobs.status='failed' is terminal (:ok, no retry)" do
      seed_job("found")
      # Simulate STEP 6's psql update writing 'failed' (listing 404 etc.)
      # before the bot exits. The worker should treat this as terminal
      # so Oban marks the job complete instead of retrying forever.
      SessionRunner.subscribe()

      set_fake_command("""
      echo '[step] 6/6 verify'
      sleep 0.3
      """)

      task = Task.async(fn -> perform_job(ApplyWorker, @args) end)

      assert_receive {:started, _}, 1_500
      from(j in Job, where: j.url == ^@job_url) |> Repo.update_all(set: [status: "failed"])

      assert :ok = Task.await(task, 5_000)
    end

    test "rate-limit line in stdout converts {:claude_exit, _} into {:snooze, _}" do
      seed_job("found")

      # Tighten the base snooze so the assertion is bounded — full
      # 2h+jitter still works, but a small window is easier to reason
      # about under test.
      Application.put_env(:linkbot, ApplyWorker, rate_limit_snooze_seconds: 60)
      on_exit(fn -> Application.delete_env(:linkbot, ApplyWorker) end)

      set_fake_command("""
      echo "You've hit your limit · resets 8:30pm (America/Santo_Domingo)"
      exit 1
      """)

      assert {:snooze, snooze} = perform_job(ApplyWorker, @args)
      assert is_integer(snooze)
      assert snooze >= 60
    end
  end

  describe "Oban.insert/1 uniqueness" do
    test "second enqueue with same job_url returns the same Oban job id" do
      {:ok, j1} = @args |> ApplyWorker.new() |> Oban.insert()
      {:ok, j2} = @args |> ApplyWorker.new() |> Oban.insert()

      assert j1.id == j2.id
    end
  end
end
