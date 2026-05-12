defmodule GraceJobs.Factory do
  @moduledoc "ExMachina factory for test data."
  use ExMachina.Ecto, repo: GraceJobs.Repo

  alias GraceJobs.Jobs.Job

  def job_factory do
    %Job{
      source: "remoteok",
      external_id: sequence(:external_id, &"ext-#{&1}"),
      title: sequence(:title, &"Senior TypeScript Engineer #{&1}"),
      company: sequence(:company, &"Acme #{&1}"),
      url: sequence(:url, &"https://example.com/job/#{&1}"),
      description: "Build modern TS apps.",
      remote: true,
      tags: ["typescript", "react"],
      role: "typescript",
      seniority: "senior",
      posted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      raw: %{}
    }
  end

  def raw_job_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        source: "remoteok",
        external_id: "raw-#{System.unique_integer([:positive])}",
        title: "Senior Backend Engineer",
        url: "https://example.com/raw",
        company: "Test Co",
        description: "We use Python and Kubernetes.",
        location: "Remote",
        remote: true,
        tags: ["python", "k8s"],
        posted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      overrides
    )
  end
end
