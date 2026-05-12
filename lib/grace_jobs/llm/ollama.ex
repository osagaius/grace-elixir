defmodule GraceJobs.LLM.Ollama do
  @moduledoc """
  Local-LLM classifier backed by Ollama (default: llama3.2:3b).

  Uses Ollama's JSON-format response mode so the model returns a strict
  object we can decode. Falls back to nil/[] if the model misbehaves.
  """
  @behaviour GraceJobs.LLM.Client

  alias GraceJobs.Jobs.Job

  @default_timeout 30_000

  @impl true
  def classify(raw) do
    cfg = Application.get_env(:grace_jobs, :llm, [])
    base_url = cfg[:base_url] || "http://localhost:11434"
    model = cfg[:model] || "llama3.2:3b"

    body = %{
      model: model,
      stream: false,
      format: "json",
      options: %{temperature: 0.1},
      prompt: prompt_for(raw),
      system: system_prompt()
    }

    case Req.post(base_url <> "/api/generate", json: body, receive_timeout: @default_timeout) do
      {:ok, %{status: 200, body: %{"response" => json_str}}} ->
        decode(json_str)

      {:ok, %{status: status, body: b}} ->
        {:error, {:http, status, b}}

      {:error, e} ->
        {:error, e}
    end
  end

  defp system_prompt do
    """
    You are a strict JSON classifier for software-engineering job postings.
    Reply with one JSON object only — no prose. Schema:

      { "role": <one of: #{Enum.join(Job.roles(), ", ")}>,
        "seniority": <one of: #{Enum.join(Job.seniorities(), ", ")}>,
        "tags": [<short lowercase technology tag>, ...] }

    Use "other" for role if none fit. Use "mid" for seniority if unclear.
    Tags should be canonical technology names (typescript, python, kubernetes,
    aws, terraform, react, postgres, etc.) — max 8.
    """
  end

  defp prompt_for(raw) do
    """
    Title: #{raw[:title] || raw["title"]}
    Company: #{raw[:company] || raw["company"]}
    Tags from source: #{Enum.join(raw[:tags] || raw["tags"] || [], ", ")}
    Description: #{String.slice(raw[:description] || raw["description"] || "", 0, 1500)}
    """
  end

  defp decode(json_str) do
    case Jason.decode(json_str) do
      {:ok, %{} = m} ->
        {:ok,
         %{
           role: normalise_role(m["role"]),
           seniority: normalise_seniority(m["seniority"]),
           tags: normalise_tags(m["tags"])
         }}

      _ ->
        {:ok, %{role: nil, seniority: nil, tags: []}}
    end
  end

  defp normalise_role(nil), do: nil

  defp normalise_role(r) do
    r = r |> to_string() |> String.downcase() |> String.trim()
    if r in Job.roles(), do: r, else: "other"
  end

  defp normalise_seniority(nil), do: nil

  defp normalise_seniority(s) do
    s = s |> to_string() |> String.downcase() |> String.trim()
    if s in Job.seniorities(), do: s, else: nil
  end

  defp normalise_tags(nil), do: []

  defp normalise_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(&(&1 |> to_string() |> String.downcase() |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(8)
  end

  defp normalise_tags(_), do: []
end
