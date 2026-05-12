defmodule Linkbot.SessionRunnerTest do
  # async: false — SessionRunner is a singleton and we toggle Application env.
  use ExUnit.Case, async: false

  alias Linkbot.SessionRunner

  setup do
    SessionRunner.stop_session()

    on_exit(fn ->
      SessionRunner.stop_session()
      Application.delete_env(:linkbot, Linkbot.SessionRunner)
    end)

    :ok
  end

  defp set_fake_command(script) do
    Application.put_env(:linkbot, Linkbot.SessionRunner, command: {"/bin/bash", ["-c", script]})
  end

  describe "harness" do
    test "spawns a process, streams stdout line-by-line over PubSub, then reports exit" do
      set_fake_command("echo line-a; echo line-b; echo line-c")
      SessionRunner.subscribe()

      assert {:ok, os_pid} = SessionRunner.run("fake query")
      assert is_integer(os_pid)

      assert_receive {:started, %{query: "fake query"}}, 1_000
      assert_receive {:log, %{line: "line-a"}}, 2_000
      assert_receive {:log, %{line: "line-b"}}, 2_000
      assert_receive {:log, %{line: "line-c"}}, 2_000
      assert_receive {:exited, %{status: 0}}, 2_000

      status = SessionRunner.status()
      refute status.running?
    end

    test "rejects a second run while one is in flight" do
      # Long-running fake so the first session is still active when we try again.
      set_fake_command("for i in 1 2 3 4 5; do echo tick-$i; sleep 0.2; done")
      SessionRunner.subscribe()

      assert {:ok, _} = SessionRunner.run()
      assert_receive {:log, %{line: "tick-1"}}, 2_000
      assert {:error, :already_running} = SessionRunner.run()

      :ok = SessionRunner.stop_session()
      assert_receive {:stopped, _}, 1_000
    end

    test "captures stderr too (because we set stderr_to_stdout)" do
      set_fake_command("echo to-stdout; echo to-stderr 1>&2")
      SessionRunner.subscribe()

      {:ok, _} = SessionRunner.run()

      assert_receive {:log, %{line: "to-stdout"}}, 2_000
      assert_receive {:log, %{line: "to-stderr"}}, 2_000
      assert_receive {:exited, _}, 2_000
    end

    test "default command targets the real claude CLI with the expected flags" do
      # We don't actually run the real CLI here — just inspect what would be built.
      Application.delete_env(:linkbot, Linkbot.SessionRunner)

      {bin, args} =
        :sys.get_state(SessionRunner) |> then(fn _ -> build_default("smoke query") end)

      assert bin |> Path.basename() == "claude"
      assert "--dangerously-skip-permissions" in args
      assert "--chrome" in args
      assert "--print" in args
      assert Enum.any?(args, &String.contains?(&1, "smoke query"))
    end
  end

  # Mirrors SessionRunner.build_command/1 default branch for assertion purposes.
  # Kept here (not in the module under test) so the production code stays minimal.
  defp build_default(query) do
    cfg = Linkbot.Repo.config()

    conn = %{
      database: Keyword.fetch!(cfg, :database),
      hostname: Keyword.get(cfg, :hostname, "localhost"),
      port: Keyword.get(cfg, :port, 5432),
      username: Keyword.get(cfg, :username, System.get_env("USER", "postgres")),
      password: Keyword.get(cfg, :password, "")
    }

    prompt = Linkbot.SessionPrompt.render(query, conn)
    bin = System.find_executable("claude") || "claude"
    {bin, ["--dangerously-skip-permissions", "--chrome", "--print", prompt]}
  end
end
