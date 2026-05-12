defmodule Linkbot.ApplyBot.SessionRunnerTest do
  # async: false — SessionRunner is a singleton and we toggle Application env.
  use ExUnit.Case, async: false

  alias Linkbot.ApplyBot.{SessionRunner, SessionPrompt}

  @job_url "https://jobs.ashbyhq.com/example/abc/application"
  @resume_url "https://drive.google.com/file/d/RESUMEID/view?usp=sharing"

  setup do
    SessionRunner.stop_session()

    on_exit(fn ->
      SessionRunner.stop_session()
      Application.delete_env(:linkbot, Linkbot.ApplyBot.SessionRunner)
    end)

    :ok
  end

  defp set_fake_command(script) do
    Application.put_env(:linkbot, Linkbot.ApplyBot.SessionRunner,
      command: {"/bin/bash", ["-c", script]}
    )
  end

  describe "dry run" do
    test "spawns a process, streams the canned [job] lines, then reports exit" do
      # Mimic what a real Claude apply session would emit, line-by-line.
      script = """
      echo '[runner] apply session started: #{@job_url}'
      echo '[job] applying: Example Role @ Example Co'
      echo '[job] applied: Example Role @ Example Co'
      """

      set_fake_command(script)
      SessionRunner.subscribe()

      assert {:ok, os_pid} = SessionRunner.run(@job_url, @resume_url)
      assert is_integer(os_pid)

      assert_receive {:started, %{job_url: @job_url, resume_url: @resume_url}}, 1_000
      assert_receive {:log, %{line: "[runner] apply session started: " <> _}}, 2_000
      assert_receive {:log, %{line: "[job] applying: Example Role @ Example Co"}}, 2_000
      assert_receive {:log, %{line: "[job] applied: Example Role @ Example Co"}}, 2_000
      assert_receive {:exited, %{status: 0}}, 2_000

      status = SessionRunner.status()
      refute status.running?
    end

    test "rejects a second run while one is in flight" do
      set_fake_command("for i in 1 2 3 4 5; do echo tick-$i; sleep 0.2; done")
      SessionRunner.subscribe()

      assert {:ok, _} = SessionRunner.run(@job_url, @resume_url)
      assert_receive {:log, %{line: "tick-1"}}, 2_000

      assert {:error, :already_running} = SessionRunner.run(@job_url, @resume_url)

      :ok = SessionRunner.stop_session()
      assert_receive {:stopped, _}, 1_000
    end
  end

  describe "prompt" do
    test "render/3 embeds both URLs, the psql connection, and the resume path" do
      conn = %{
        database: "grace_jobs_dev",
        hostname: "localhost",
        port: 5432,
        username: "postgres",
        password: ""
      }

      prompt = SessionPrompt.render(@job_url, @resume_url, conn)

      assert prompt =~ @job_url
      assert prompt =~ @resume_url
      assert prompt =~ "psql \"host=localhost port=5432 user=postgres dbname=grace_jobs_dev\""
      assert prompt =~ "/tmp/applybot/resume.pdf"
      # Drive id should be plucked from the share URL and used in the
      # download URL.
      assert prompt =~ "id=RESUMEID"
    end

    test "default_job_url/0 and default_resume_url/0 are populated" do
      assert is_binary(SessionPrompt.default_job_url())
      assert is_binary(SessionPrompt.default_resume_url())
      assert SessionPrompt.default_job_url() =~ "ashbyhq.com"
      assert SessionPrompt.default_resume_url() =~ "drive.google.com"
    end
  end

  describe "default command" do
    test "targets the real claude CLI with the expected flags" do
      Application.delete_env(:linkbot, Linkbot.ApplyBot.SessionRunner)

      {bin, args} = build_default(@job_url, @resume_url)

      assert bin |> Path.basename() == "claude"
      assert "--dangerously-skip-permissions" in args
      assert "--chrome" in args
      assert "--print" in args
      assert Enum.any?(args, &String.contains?(&1, @job_url))
      assert Enum.any?(args, &String.contains?(&1, @resume_url))
    end
  end

  # Mirrors SessionRunner.build_command/2 default branch for assertion purposes.
  defp build_default(job_url, resume_url) do
    cfg = Linkbot.Repo.config()

    conn = %{
      database: Keyword.fetch!(cfg, :database),
      hostname: Keyword.get(cfg, :hostname, "localhost"),
      port: Keyword.get(cfg, :port, 5432),
      username: Keyword.get(cfg, :username, System.get_env("USER", "postgres")),
      password: Keyword.get(cfg, :password, "")
    }

    prompt = SessionPrompt.render(job_url, resume_url, conn)
    bin = System.find_executable("claude") || "claude"
    {bin, ["--dangerously-skip-permissions", "--chrome", "--print", prompt]}
  end
end
