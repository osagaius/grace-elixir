defmodule Linkbot.JobsFixtures do
  @moduledoc "Test helpers for the central `jobs` table."

  def job_fixture(attrs \\ %{}) do
    uniq = System.unique_integer([:positive, :monotonic])

    {:ok, job} =
      attrs
      |> Enum.into(%{
        source: "linkedin",
        external_id: "fixture-#{uniq}",
        title: "Backend Engineer",
        company: "Acme",
        url: "https://www.linkedin.com/jobs/view/#{uniq}",
        location: "Remote",
        remote: true,
        status: "found",
        notes: "",
        source_company: nil
      })
      |> Map.delete(:source_company)
      |> Linkbot.Jobs.create_job()

    job
  end
end
