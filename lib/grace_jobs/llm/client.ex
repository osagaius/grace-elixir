defmodule GraceJobs.LLM.Client do
  @moduledoc """
  Behaviour for an LLM classifier. Given a raw job map, return
  classification fields (`role`, `seniority`, normalised `tags`).
  """
  @callback classify(raw_job :: map()) ::
              {:ok, %{role: String.t() | nil, seniority: String.t() | nil, tags: [String.t()]}}
              | {:error, term()}
end
