defmodule GraceJobs.Scrapers.ComputerUse do
  @moduledoc """
  Wraps Anthropic's computer-use beta. Drives a browser session via the
  agent loop (screenshot/click/type tool actions) to extract job data
  from boards that don't expose JSON or RSS.

  This module is intentionally agnostic about how the actual desktop is
  hosted — you pass in a `BrowserHost` module via `:host_mod` that
  implements `screenshot/0`, `click/2`, `type/1`, etc. In dev/test we
  ship `GraceJobs.Scrapers.ComputerUse.NullHost` which returns canned
  responses so the agent loop can be tested without real network/browser
  access.

  This is the slower / more expensive scraping path. Prefer the JSON or
  RSS scrapers above for sources that publish a feed.
  """
  @behaviour GraceJobs.Scrapers.Scraper

  alias GraceJobs.Scrapers.ComputerUse.NullHost

  require Logger

  @anthropic_version "2023-06-01"
  @beta "computer-use-2025-01-24"

  @impl true
  def fetch(opts \\ []) do
    target_url = Keyword.fetch!(opts, :target_url)
    instructions = Keyword.get(opts, :instructions, default_instructions(target_url))
    host_mod = Keyword.get(opts, :host_mod, NullHost)
    api = Keyword.get(opts, :api, &call_anthropic/1)
    max_steps = Keyword.get(opts, :max_steps, 25)

    state = %{
      messages: [%{role: "user", content: instructions}],
      host: host_mod,
      api: api,
      steps: 0,
      max_steps: max_steps,
      collected: []
    }

    case agent_loop(state) do
      {:ok, %{collected: jobs}} -> {:ok, jobs}
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_instructions(url) do
    """
    Open a browser and navigate to #{url}. Read the visible job listings
    on the page. For each listing, extract: title, company, url,
    description (1 paragraph), tags. When you have a structured list,
    return the JSON via the `submit_jobs` tool. Stop after submitting.
    """
  end

  defp agent_loop(%{steps: s, max_steps: m}) when s >= m, do: {:error, :max_steps}

  defp agent_loop(state) do
    body = %{
      model: anthropic_model(),
      max_tokens: 4096,
      tools: tools(),
      messages: state.messages
    }

    case state.api.(body) do
      {:ok, %{"stop_reason" => "tool_use", "content" => content}} ->
        state
        |> apply_tool_calls(content)
        |> Map.update!(:steps, &(&1 + 1))
        |> agent_loop()

      {:ok, %{"stop_reason" => stop, "content" => content}} when stop in ["end_turn", "stop_sequence"] ->
        {:ok, %{state | collected: extract_jobs_from_content(content) ++ state.collected}}

      {:ok, other} ->
        Logger.warning("computer-use unexpected response: #{inspect(other)}")
        {:error, :unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp tools do
    [
      %{
        type: "computer_20250124",
        name: "computer",
        display_width_px: 1280,
        display_height_px: 800,
        display_number: 1
      },
      %{
        name: "submit_jobs",
        description: "Submit the structured list of jobs you extracted from the page.",
        input_schema: %{
          type: "object",
          properties: %{
            jobs: %{
              type: "array",
              items: %{
                type: "object",
                properties: %{
                  title: %{type: "string"},
                  company: %{type: "string"},
                  url: %{type: "string"},
                  description: %{type: "string"},
                  tags: %{type: "array", items: %{type: "string"}}
                },
                required: ["title", "url"]
              }
            }
          },
          required: ["jobs"]
        }
      }
    ]
  end

  defp apply_tool_calls(state, content) do
    Enum.reduce(content, state, fn block, acc ->
      case block do
        %{"type" => "tool_use", "name" => "computer", "id" => id, "input" => input} ->
          result = dispatch_computer(acc.host, input)
          add_tool_result(acc, id, result)

        %{"type" => "tool_use", "name" => "submit_jobs", "id" => id, "input" => %{"jobs" => jobs}} ->
          collected =
            jobs
            |> Enum.map(&job_to_raw/1)
            |> Enum.reject(&is_nil/1)

          %{add_tool_result(acc, id, "ok") | collected: collected ++ acc.collected}

        _ ->
          acc
      end
    end)
  end

  defp dispatch_computer(host, %{"action" => "screenshot"}) do
    case host.screenshot() do
      {:ok, b64} -> %{type: "image", source: %{type: "base64", media_type: "image/png", data: b64}}
      {:error, _} -> "screenshot failed"
    end
  end

  defp dispatch_computer(host, %{"action" => "left_click", "coordinate" => [x, y]}) do
    host.click(x, y)
    "clicked"
  end

  defp dispatch_computer(host, %{"action" => "type", "text" => text}) do
    host.type(text)
    "typed"
  end

  defp dispatch_computer(_host, action) do
    "unsupported action: #{inspect(action)}"
  end

  defp add_tool_result(state, tool_use_id, result) do
    assistant_msg = %{role: "assistant", content: List.wrap(result)}

    user_msg = %{
      role: "user",
      content: [%{type: "tool_result", tool_use_id: tool_use_id, content: List.wrap(result)}]
    }

    %{state | messages: state.messages ++ [assistant_msg, user_msg]}
  end

  defp job_to_raw(%{"title" => title, "url" => url} = j) do
    %{
      source: Map.get(j, "source", "computer_use"),
      external_id: url,
      title: title,
      url: url,
      company: j["company"],
      description: j["description"],
      remote: true,
      tags: List.wrap(j["tags"] || []),
      posted_at: nil,
      raw: j
    }
  end

  defp job_to_raw(_), do: nil

  defp extract_jobs_from_content(content) do
    content
    |> Enum.flat_map(fn
      %{"type" => "tool_use", "name" => "submit_jobs", "input" => %{"jobs" => jobs}} ->
        Enum.map(jobs, &job_to_raw/1)

      _ ->
        []
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp anthropic_model do
    Application.get_env(:grace_jobs, :anthropic, [])[:model] || "claude-opus-4-7"
  end

  defp call_anthropic(body) do
    cfg = Application.get_env(:grace_jobs, :anthropic, [])
    api_key = cfg[:api_key] || System.get_env("ANTHROPIC_API_KEY")
    base_url = cfg[:base_url] || "https://api.anthropic.com"

    if is_nil(api_key) do
      {:error, :missing_api_key}
    else
      Req.post(base_url <> "/v1/messages",
        json: body,
        headers: [
          {"x-api-key", api_key},
          {"anthropic-version", @anthropic_version},
          {"anthropic-beta", @beta}
        ]
      )
      |> case do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: s, body: b}} -> {:error, {:http, s, b}}
        {:error, e} -> {:error, e}
      end
    end
  end
end
