defmodule Linkbot.ApplyBot.TrabaCompletionTest do
  @moduledoc """
  Integration-style test that stubs the Claude binary with a bash
  script that walks the full happy-path lifecycle for the real Traba
  application URL.

  The stub does two things at every step:

    1. Writes a real artifact file to disk (screenshot PNG, page HTML)
       in a per-test artifact directory.
    2. Emits the structured `[step]` + `[artifact]` marker lines the
       prompt requires.

  The test then asserts that:

    * SessionRunner captures all 6 expected step slugs.
    * SessionRunner captures all 12 expected artifact entries.
    * Every artifact path Claude advertised is a real, non-empty file.
    * The lifecycle log lines stream through PubSub in order, ending
      with `[job] applied:` and a clean exit.

  This pins the **contract** between the prompt and the harness: any
  future change to the prompt's marker syntax will break this test, so
  the harness will stay in sync.
  """

  # async: false — SessionRunner is a singleton.
  use ExUnit.Case, async: false

  alias Linkbot.ApplyBot.SessionRunner

  @job_url "https://jobs.ashbyhq.com/traba/a2a2bfb5-7ba1-4035-af22-bd6691e66575/application?utm_source=Q72aonZnRG"
  @resume_url "https://drive.google.com/file/d/1TjPuZqJKyZqHyZg53ea_4pq6IjRysdZK/view?usp=sharing"

  @steps [
    {1, "download"},
    {2, "db-row"},
    {3, "open-page"},
    {4, "fill-form"},
    {5, "submit"},
    {6, "verify"}
  ]

  setup do
    SessionRunner.stop_session()

    # Per-test artifact dir so we don't clobber real runs.
    dir = Path.join(System.tmp_dir!(), "applybot-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "screenshots"))
    File.mkdir_p!(Path.join(dir, "html"))

    on_exit(fn ->
      SessionRunner.stop_session()
      Application.delete_env(:linkbot, Linkbot.ApplyBot.SessionRunner)
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir}
  end

  test "stub session walks all 6 steps, writes 12 artifacts, ends in applied",
       %{dir: dir} do
    Application.put_env(:linkbot, Linkbot.ApplyBot.SessionRunner,
      command: {"/bin/bash", ["-c", happy_path_script(dir)]}
    )

    SessionRunner.subscribe()

    {:ok, _pid} = SessionRunner.run(@job_url, @resume_url)

    assert_receive {:started, %{job_url: @job_url, resume_url: @resume_url}}, 1_000

    # 1. Step markers — one event per step, in numeric order.
    for {n, slug} <- @steps do
      assert_receive {:step, %{n: ^n, total: 6, slug: ^slug}}, 3_000
    end

    # 2. Artifact markers — one screenshot + one html per step,
    #    pointing at files that actually exist on disk.
    for {n, slug} <- @steps do
      screenshot = Path.join(dir, "screenshots/step-#{n}-#{slug}.png")
      html = Path.join(dir, "html/step-#{n}-#{slug}.html")

      assert_receive {:artifact, %{kind: "screenshot", path: ^screenshot}}, 3_000
      assert_receive {:artifact, %{kind: "html", path: ^html}}, 3_000

      assert File.exists?(screenshot), "expected screenshot at #{screenshot}"
      assert File.exists?(html), "expected html dump at #{html}"
      assert File.stat!(screenshot).size > 0
      assert File.stat!(html).size > 0
    end

    # 3. Final lifecycle: [job] applied + clean exit.
    assert_receive {:log, %{line: "[job] applied: Staff Software Engineer @ Traba"}}, 3_000
    assert_receive {:exited, %{status: 0}}, 3_000

    # 4. SessionRunner.status reflects the same picture the test
    #    observed via PubSub.
    status = SessionRunner.status()
    refute status.running?
    assert MapSet.equal?(status.steps, MapSet.new(Enum.map(@steps, &elem(&1, 1))))
    assert length(status.artifacts) == 12

    {screenshots, htmls} =
      Enum.split_with(status.artifacts, &(&1.kind == "screenshot"))

    assert length(screenshots) == 6
    assert length(htmls) == 6
  end

  test "if a step is skipped, status.steps reflects the gap", %{dir: dir} do
    # Stub that completes only the first 4 steps then exits — simulates
    # an interruption between fill-form and submit. The harness should
    # NOT claim submit/verify happened.
    partial_script = """
    set -euo pipefail
    DIR=#{dir}
    mkdir -p "$DIR/screenshots" "$DIR/html"
    #{step_block(dir, 1, "download")}
    #{step_block(dir, 2, "db-row")}
    #{step_block(dir, 3, "open-page")}
    #{step_block(dir, 4, "fill-form")}
    echo '[runner] human verification required'
    """

    Application.put_env(:linkbot, Linkbot.ApplyBot.SessionRunner,
      command: {"/bin/bash", ["-c", partial_script]}
    )

    SessionRunner.subscribe()
    {:ok, _} = SessionRunner.run(@job_url, @resume_url)

    assert_receive {:exited, _}, 3_000

    status = SessionRunner.status()

    assert MapSet.equal?(
             status.steps,
             MapSet.new(["download", "db-row", "open-page", "fill-form"])
           )

    refute "submit" in status.steps
    refute "verify" in status.steps
  end

  # ── Stub-script builders ────────────────────────────────────────────────

  defp happy_path_script(dir) do
    body =
      Enum.map_join(@steps, "\n", fn {n, slug} -> step_block(dir, n, slug) end)

    """
    set -euo pipefail
    DIR=#{dir}
    mkdir -p "$DIR/screenshots" "$DIR/html"
    echo '[runner] apply session started: #{@job_url}'
    echo '[job] applying: Staff Software Engineer @ Traba'
    #{body}
    echo '[job] applied: Staff Software Engineer @ Traba'
    """
  end

  # One step's worth of bash: write artifact files, emit the three
  # marker lines the harness expects.
  defp step_block(dir, n, slug) do
    screenshot = Path.join(dir, "screenshots/step-#{n}-#{slug}.png")
    html = Path.join(dir, "html/step-#{n}-#{slug}.html")

    """
    printf 'PNG\\n' > #{screenshot}
    printf '<html><body>step %s %s</body></html>\\n' #{n} #{slug} > #{html}
    echo '[step] #{n}/6 #{slug}'
    echo '[artifact] screenshot: #{screenshot}'
    echo '[artifact] html: #{html}'
    """
  end
end
