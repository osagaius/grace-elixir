defmodule GraceJobs.Scrapers.Scraper do
  @moduledoc """
  Behaviour every job-source scraper must implement.

  A scraper returns a list of "raw job" maps with the canonical keys we
  expect downstream — see `t:raw_job/0`. Normalisation, classification,
  and persistence happen in later pipeline stages, never here.
  """

  @type raw_job :: %{
          required(:source) => String.t(),
          required(:external_id) => String.t(),
          required(:title) => String.t(),
          required(:url) => String.t(),
          optional(:company) => String.t() | nil,
          optional(:description) => String.t() | nil,
          optional(:location) => String.t() | nil,
          optional(:remote) => boolean(),
          optional(:tags) => [String.t()],
          optional(:posted_at) => DateTime.t() | nil,
          optional(:raw) => map()
        }

  @callback fetch(opts :: keyword()) :: {:ok, [raw_job()]} | {:error, term()}
end
