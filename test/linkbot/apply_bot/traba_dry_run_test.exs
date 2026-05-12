defmodule Linkbot.ApplyBot.TrabaDryRunTest do
  @moduledoc """
  Dry-run smoke test against the real Traba application URL.

  This test does NOT launch Claude or Chrome — it stubs the spawned binary
  with `/bin/bash -c "<echoed apply lifecycle>"` so we can verify that:

    1. SessionPrompt.render/3 produces a prompt that mentions this exact
       URL, the Drive resume id, the resume path, and the right psql conn.
    2. SessionRunner spawns, streams the lifecycle lines via PubSub, and
       reports a clean exit — i.e. nothing would crash if Claude itself
       emitted those lines.
  """

  use ExUnit.Case, async: false

  alias Linkbot.ApplyBot.{SessionPrompt, SessionRunner}

  @job_url "https://jobs.ashbyhq.com/traba/a2a2bfb5-7ba1-4035-af22-bd6691e66575/application?utm_source=Q72aonZnRG"
  @resume_url "https://drive.google.com/file/d/1TjPuZqJKyZqHyZg53ea_4pq6IjRysdZK/view?usp=sharing"

  setup do
    SessionRunner.stop_session()

    on_exit(fn ->
      SessionRunner.stop_session()
      Application.delete_env(:linkbot, Linkbot.ApplyBot.SessionRunner)
    end)

    :ok
  end

  test "prompt renders cleanly for the Traba URL" do
    cfg = Linkbot.Repo.config()

    conn = %{
      database: Keyword.fetch!(cfg, :database),
      hostname: Keyword.get(cfg, :hostname, "localhost"),
      port: Keyword.get(cfg, :port, 5432),
      username: Keyword.get(cfg, :username, System.get_env("USER", "postgres")),
      password: Keyword.get(cfg, :password, "")
    }

    prompt = SessionPrompt.render(@job_url, @resume_url, conn)

    assert prompt =~ @job_url
    assert prompt =~ @resume_url
    # Drive file id pulled out of the share URL and reused in the
    # direct-download curl line.
    assert prompt =~ "id=1TjPuZqJKyZqHyZg53ea_4pq6IjRysdZK"
    assert prompt =~ "/tmp/applybot/resume.pdf"
    assert prompt =~ ~r{psql "host=.+ port=\d+ user=.+ dbname=.+"}
    # Per-event tags the LiveView log panel grep-highlights.
    assert prompt =~ "[job] applying:"
    assert prompt =~ "[job] applied:"
    assert prompt =~ "[job] skipped:"
    assert prompt =~ "[job] failed:"
  end

  test "harness runs the full apply lifecycle against the Traba URL (stubbed)" do
    # Stand in for Claude. We echo the same tagged lines a real session
    # would emit so we can verify the PubSub stream end-to-end.
    fake_apply_run = """
    echo '[runner] apply session started: #{@job_url}'
    echo '[job] applying: Engineer @ Traba'
    sleep 0.05
    echo '[job] applied: Engineer @ Traba'
    """

    Application.put_env(:linkbot, Linkbot.ApplyBot.SessionRunner,
      command: {"/bin/bash", ["-c", fake_apply_run]}
    )

    SessionRunner.subscribe()

    assert {:ok, os_pid} = SessionRunner.run(@job_url, @resume_url)
    assert is_integer(os_pid)

    assert_receive {:started, %{job_url: @job_url, resume_url: @resume_url}}, 1_000
    assert_receive {:log, %{line: "[runner] apply session started: " <> _}}, 2_000
    assert_receive {:log, %{line: "[job] applying: Engineer @ Traba"}}, 2_000
    assert_receive {:log, %{line: "[job] applied: Engineer @ Traba"}}, 2_000
    assert_receive {:exited, %{status: 0}}, 2_000

    refute SessionRunner.status().running?
  end
end
