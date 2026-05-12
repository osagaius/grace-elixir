defmodule Linkbot.ApplyBot.SessionPrompt do
  @moduledoc """
  Builds the prompt handed to the ApplyBot Claude session — a single job
  application using a resume hosted at a public URL (e.g. a Google Drive
  share link).

  The prompt is structured around six numbered checkpoint steps. Claude
  must emit two kinds of structured marker lines that `SessionRunner`
  parses:

      [step] N/6 <slug>
      [artifact] <kind>: <absolute-path>

  Both are surfaced via the GenServer status, the LiveView dashboard,
  and the test suite, so we can verify the bot actually went through
  every step and saved a screenshot + HTML dump at each one.
  """

  alias Linkbot.ApplyBot.Profile

  @default_job_url "https://jobs.ashbyhq.com/traba/a2a2bfb5-7ba1-4035-af22-bd6691e66575/application?utm_source=Q72aonZnRG"
  @default_resume_url "https://drive.google.com/file/d/1TjPuZqJKyZqHyZg53ea_4pq6IjRysdZK/view?usp=sharing"

  @artifact_dir "/tmp/applybot"

  def default_job_url, do: @default_job_url
  def default_resume_url, do: @default_resume_url
  def artifact_dir, do: @artifact_dir

  @doc """
  Render the full prompt. `conn` is a Postgres connection map with keys
  :database, :hostname, :port, :username, :password.
  """
  def render(job_url, resume_url, conn) do
    db = Map.fetch!(conn, :database)
    host = Map.get(conn, :hostname, "localhost")
    port = Map.get(conn, :port, 5432)
    user = Map.get(conn, :username, System.get_env("USER", "postgres"))

    psql = ~s|psql "host=#{host} port=#{port} user=#{user} dbname=#{db}"|
    drive_id = extract_drive_id(resume_url)
    resume_path = "#{@artifact_dir}/resume.pdf"
    profile = Profile.current()

    download_cmd =
      if drive_id do
        ~s|curl -L -o #{resume_path} "https://drive.google.com/uc?export=download&id=#{drive_id}"|
      else
        ~s|curl -L -o #{resume_path} "#{resume_url}"|
      end

    """
    You are an autonomous job-application agent. You have access to:
      - Chrome via the claude-in-chrome MCP (read_page, click, form_input,
        navigate, javascript_tool, get_page_text, etc.)
      - A local Postgres database via the `psql` CLI.
      - A shell with `curl`, `pdftotext`, `screencapture`, and `mkdir`
        on PATH.

    THIS RUN APPLIES TO A SINGLE JOB:
        job url: #{job_url}
        resume:  #{resume_url}

    GOAL: complete every required field of this application and click
    the submit button. Skipping is a LAST RESORT and must be justified —
    the answer profile below covers the questions most ATSes ask, so use
    it. Don't bail on screening questions you have an answer for.

    ── ANSWER PROFILE — use these values for screening questions ──

    #{render_profile(profile)}

    For free-form essay boxes ("Why this company?", "What interests you
    about this role?", "Tell us about a recent project"), don't paste
    the seed verbatim. Paraphrase the seed against this specific role's
    posted description (which you'll have read from the page in STEP 2)
    in 3–5 concrete sentences. Never invent facts that aren't on the
    resume or in this profile.

    ── ARTIFACT REQUIREMENT — at the end of EVERY step ──

    Save TWO files and emit TWO marker lines so the harness can verify
    you reached that step:

      1. Screenshot of the current Chrome viewport →
           #{@artifact_dir}/screenshots/step-N-<slug>.png
         If the claude-in-chrome MCP exposes a screenshot tool, use it.
         Otherwise fall back to:
           screencapture -x #{@artifact_dir}/screenshots/step-N-<slug>.png

      2. HTML or text dump of the current page →
           #{@artifact_dir}/html/step-N-<slug>.html
         Use the claude-in-chrome MCP's `read_page` (or `get_page_text`)
         tool and write its output to that file.

    Then print these two lines (they MUST match these exact patterns —
    the harness regex-matches them):

        [step] N/6 <slug>
        [artifact] screenshot: #{@artifact_dir}/screenshots/step-N-<slug>.png
        [artifact] html: #{@artifact_dir}/html/step-N-<slug>.html

    The six steps and their required <slug>s are: download, db-row,
    open-page, fill-form, submit, verify. Step numbers map 1→6.

    ── STEP 0 — PREPARE ARTIFACT DIRS ──
        Run these once:
            mkdir -p #{@artifact_dir}/screenshots #{@artifact_dir}/html

    ── STEP 1 — DOWNLOAD THE RESUME (slug: download) ──
        Run:
            #{download_cmd}

        Verify the file is a real PDF:
            file #{resume_path}
        If `file` says HTML (Drive interstitial), parse the confirm
        token out of the HTML body and retry the curl with
        `&confirm=<token>` appended. If that still fails after one
        retry, print:
            [runner] resume download failed — needs manual help
        and exit.

        On success: there is no page to screenshot for this step, so
        take a screenshot of the desktop and dump `ls -lh #{resume_path}`
        output into the html file. Emit the three marker lines.

    ── STEP 2 — LOCATE / CREATE THE JOBS ROW (slug: db-row) ──
        Look up the row by URL:
            #{psql} -At -c "SELECT id, status FROM jobs WHERE url='#{job_url}' LIMIT 1;"

        - If status='applied' → print:
              [job] already-applied: #{job_url}
            and stop. Do not re-apply.
        - If any other status → UPDATE to 'applying'.
        - If no row → INSERT one. source = the URL's host (e.g. 'ashby'
          for jobs.ashbyhq.com). external_id = a stable slug from the
          URL path (last UUID segment is fine). Use ON CONFLICT
          (source, external_id) DO UPDATE SET status='applying'.

            #{psql} -c "UPDATE jobs SET status='applying', updated_at=now() WHERE url='#{job_url}';"

        Take desktop screenshot + dump the psql output as html. Emit
        markers.

    ── STEP 3 — OPEN THE APPLICATION PAGE (slug: open-page) ──
        Open the job URL in Chrome. Wait until the form is fully
        rendered (every input has its label visible). Read the page
        and capture: TITLE, COMPANY, the full role description text
        (you'll quote from it in essay answers).

        Screenshot the rendered page + dump page HTML. Emit markers.

    ── STEP 4 — FILL THE FORM (slug: fill-form) ──
        Use `pdftotext #{resume_path} -` to extract resume text once
        and hold it in working memory. For each visible field, decide
        the value with this priority:

            1. Resume (name, email, phone, links, current role, etc.)
            2. Answer profile above (work auth, salary, location, etc.)
            3. For essay/free-form: paraphrase the profile's
               why_this_company_seed against the role description from
               STEP 3 (3–5 sentences, concrete, no invented facts).

        Upload #{resume_path} to the resume field.

        Walk every required field. If you reach a required field that
        cannot be answered from sources 1–3 (e.g. a custom multi-part
        question whose answer truly isn't on the resume or in the
        profile), DO NOT skip the whole application. Instead:
          a) Print [runner] need answer: "<exact question>"
          b) Use a best-effort answer derived from the profile's
             why_this_company_seed and continue.

        After every required field has been filled but BEFORE clicking
        submit: screenshot + dump page HTML. Emit markers. Print one
        line per field actually filled, in the form:
            [fill] <field-label>: <value-or-truncated>

    ── STEP 5 — SUBMIT (slug: submit) ──
        Click the submit / send / apply button. Wait until the page
        navigates or shows a confirmation banner.

        If a captcha or 2FA appears: pause, print
            [runner] human verification required
        and wait. Do not click submit a second time.

        Screenshot + dump page HTML immediately after click. Emit
        markers.

    ── STEP 6 — VERIFY + RECORD (slug: verify) ──
        Confirm the success state by reading the page for any of:
        "thanks for applying", "application submitted", "application
        received", "we've received your application".

        On success:
            #{psql} -c "UPDATE jobs SET status='applied', applied_at=now(), updated_at=now() WHERE url='#{job_url}';"
        Print:
            [job] applied: TITLE @ COMPANY

        On clear failure (error banner, form still showing required
        errors):
            #{psql} -c "UPDATE jobs SET status='failed', notes='ERROR_TEXT', updated_at=now() WHERE url='#{job_url}';"
        Print:
            [job] failed: TITLE @ COMPANY — ERROR_TEXT

        Screenshot + dump page HTML. Emit markers.

    ── PROGRESS LOG TAGS (one line per state change) ──
        [job] applying:        TITLE @ COMPANY
        [job] applied:         TITLE @ COMPANY
        [job] skipped:         TITLE @ COMPANY — reason
        [job] failed:          TITLE @ COMPANY — error
        [job] already-applied: URL
        [fill] <field>: <value>
        [step] N/6 <slug>
        [artifact] screenshot: <path>
        [artifact] html: <path>
        [runner] need answer: "<question>"
        [runner] human verification required

    ── SAFETY ──
      - Never invent data outside the resume + answer profile.
      - Never click withdraw / decline / edit-profile.
      - On captcha or login wall, pause and wait. Do not retry submit.

    Begin now.
    """
  end

  defp render_profile(profile) do
    profile
    |> Enum.sort_by(fn {k, _v} -> Atom.to_string(k) end)
    |> Enum.map_join("\n", fn {k, v} -> "    #{k}: #{v}" end)
  end

  defp extract_drive_id(url) when is_binary(url) do
    cond do
      match = Regex.run(~r{/file/d/([^/]+)}, url) ->
        Enum.at(match, 1)

      match = Regex.run(~r{[?&]id=([^&]+)}, url) ->
        Enum.at(match, 1)

      true ->
        nil
    end
  end

  defp extract_drive_id(_), do: nil
end
