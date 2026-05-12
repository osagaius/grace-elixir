defmodule GraceJobsWeb.JobsLiveTest do
  use GraceJobsWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import GraceJobs.Factory

  alias GraceJobs.Jobs

  describe "GET /" do
    setup do
      insert(:job,
        title: "Senior TypeScript Engineer",
        role: "typescript",
        source: "remoteok",
        tags: ["typescript", "react"]
      )

      insert(:job,
        title: "Kubernetes SRE",
        role: "kubernetes",
        source: "hackernews",
        tags: ["k8s", "aws"]
      )

      :ok
    end

    test "renders the jobs list", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Grace — daily software jobs"
      assert html =~ "Senior TypeScript Engineer"
      assert html =~ "Kubernetes SRE"
    end

    test "today_count badge shows total of today's jobs", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      assert view |> element("#today-count") |> render() =~ "2"
    end

    test "filtering by role narrows the list", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      view
      |> form("#job-filters", filter: %{role: "typescript", source: "", tag: ""})
      |> render_change()

      html = render(view)
      assert html =~ "Senior TypeScript Engineer"
      refute html =~ "Kubernetes SRE"
    end

    test "filtering by tag narrows the list", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      view
      |> form("#job-filters", filter: %{role: "", source: "", tag: "k8s"})
      |> render_change()

      html = render(view)
      refute html =~ "Senior TypeScript Engineer"
      assert html =~ "Kubernetes SRE"
    end

    test "clearing filters restores all jobs", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/?role=python")
      refute render(view) =~ "Senior TypeScript Engineer"

      view |> element("button", "Clear filters") |> render_click()
      html = render(view)
      assert html =~ "Senior TypeScript Engineer"
      assert html =~ "Kubernetes SRE"
    end

    test "live PubSub: a newly upserted job appears without reload", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      refute render(view) =~ "BRAND NEW LIVE JOB"

      {:ok, _job} =
        Jobs.upsert_job(
          raw_job_attrs(%{
            title: "BRAND NEW LIVE JOB",
            external_id: "live-1",
            url: "https://example.com/live"
          })
        )

      # Allow PubSub message to be handled by the LV process.
      Process.sleep(100)
      assert render(view) =~ "BRAND NEW LIVE JOB"
    end
  end
end
