defmodule LinkbotWeb.JobsLiveTest do
  use LinkbotWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Linkbot.JobsFixtures

  alias Linkbot.SessionRunner

  describe "/" do
    test "renders empty state and the Run session button when there are no jobs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Linkbot"
      assert html =~ "Run session"
      assert html =~ "No jobs match the current filter"
      assert html =~ "Senior Backend Engineer, Remote"
    end

    test "renders job rows from the database", %{conn: conn} do
      job_fixture(%{
        title: "Staff Backend Engineer",
        company: "Acme",
        external_id: "100",
        url: "https://www.linkedin.com/jobs/view/100",
        status: "applied",
        applied_at: ~N[2026-05-08 12:00:00]
      })

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Staff Backend Engineer"
      assert html =~ "Acme"
      assert html =~ "applied"
      refute html =~ "No jobs yet"
    end

    test "filters job rows to applied jobs", %{conn: conn} do
      applied =
        job_fixture(%{
          title: "Applied Engineer",
          external_id: "applied-300",
          status: "applied"
        })

      found =
        job_fixture(%{
          title: "Found Engineer",
          external_id: "found-300",
          status: "found"
        })

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#job-#{applied.id}")
      assert has_element?(view, "#job-#{found.id}")

      view
      |> element("#job-filters")
      |> render_change(%{"filter" => %{"applied_only" => "true"}})

      assert_patch(view, ~p"/?applied_only=true")
      assert has_element?(view, "#job-#{applied.id}")
      refute has_element?(view, "#job-#{found.id}")
    end

    test "live-updates when a job is created via the context", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert render(view) =~ "No jobs match the current filter"

      {:ok, _job} =
        Linkbot.Jobs.create_job(%{
          source: "linkedin",
          external_id: "200",
          title: "Distributed Systems Engineer",
          company: "Cosmos",
          url: "https://www.linkedin.com/jobs/view/200",
          status: "found"
        })

      html = render(view)
      assert html =~ "Distributed Systems Engineer"
      assert html =~ "Cosmos"
      refute html =~ "No jobs yet"
    end
  end

  describe "session log streaming" do
    setup do
      SessionRunner.stop_session()

      Application.put_env(:linkbot, SessionRunner,
        command:
          {"/bin/bash", ["-c", "echo claude-says-hello; echo about-to-open-chrome; echo done"]}
      )

      on_exit(fn ->
        SessionRunner.stop_session()
        Application.delete_env(:linkbot, SessionRunner)
      end)

      :ok
    end

    test "clicking Run streams the session's stdout into the log panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("button", "Run session") |> render_click()

      # Wait for the runner to flush all log lines into the LiveView.
      # The runner broadcasts {:log, _} messages which the LV folds into its
      # `:log` assign. We poll the rendered HTML for up to ~2s.
      html = wait_for(fn -> render(view) end, &String.contains?(&1, "done"), 2_000)

      assert html =~ "claude-says-hello"
      assert html =~ "about-to-open-chrome"
      assert html =~ "done"
      # Status flips to running on :started, then back to idle on :exited.
      assert html =~ "idle" or html =~ "running"
    end
  end

  defp wait_for(fun, predicate, timeout_ms, step \\ 50) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for(fun, predicate, deadline, step)
  end

  defp do_wait_for(fun, predicate, deadline, step) do
    value = fun.()

    cond do
      predicate.(value) ->
        value

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("wait_for timeout — last value:\n#{inspect(value)}")

      true ->
        Process.sleep(step)
        do_wait_for(fun, predicate, deadline, step)
    end
  end
end
