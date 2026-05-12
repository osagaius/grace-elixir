defmodule Linkbot.ApplyBot.Profile do
  @moduledoc """
  Answers ApplyBot uses to fill screening questions whose answers aren't
  on the resume (work auth, sponsorship, salary, location, essay-style
  "why this company" boxes, etc).

  The values in `defaults/0` below are placeholders — edit them before
  running ApplyBot for real, or override per-run via:

      Application.put_env(:linkbot, Linkbot.ApplyBot.Profile, overrides: %{...})

  These are rendered into the prompt verbatim, so Claude treats them as
  the source of truth instead of either guessing or skipping the
  application.
  """

  @defaults %{
    # Work authorization
    work_authorization: "Yes — authorized to work in the United States without sponsorship.",
    requires_sponsorship: "No.",

    # Location
    current_location: "New York, NY",
    willing_to_relocate: "Open to relocating to NYC or SF for the right role.",
    can_work_in_office: "Yes — open to 5x/week in-person in NYC or SF.",

    # Compensation
    salary_expectation: "Open to discussion based on total comp; targeting $200k–$240k base.",
    notice_period: "Two weeks.",

    # Demographics — these are voluntary on most ATSes; default to
    # "prefer not to say" so we never invent answers.
    gender: "Prefer not to say.",
    race_ethnicity: "Prefer not to say.",
    veteran_status: "Prefer not to say.",
    disability_status: "Prefer not to say.",

    # Free-text fallback. Claude is expected to paraphrase this against
    # the role's posted description, not paste it verbatim.
    why_this_company_seed:
      "I build pragmatic, production-quality systems and care about owning a feature end-to-end. The role's mix of product velocity and infrastructure depth is what I'm looking for next."
  }

  @doc "Profile map used to fill the form. Merges any per-run overrides on top."
  def current do
    overrides =
      Application.get_env(:linkbot, __MODULE__, [])
      |> Keyword.get(:overrides, %{})

    Map.merge(@defaults, overrides)
  end

  @doc false
  def defaults, do: @defaults
end
