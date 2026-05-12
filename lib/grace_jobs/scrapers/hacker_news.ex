defmodule GraceJobs.Scrapers.HackerNews do
  @moduledoc """
  Pulls "Who is hiring?" comments from the latest HN thread via the
  public Firebase API. The thread ID can be passed via `:thread_id` for
  testing. In production we look up "whoishiring" submissions and pick
  the most recent "Ask HN: Who is hiring" story.
  """
  @behaviour GraceJobs.Scrapers.Scraper

  @user_agent "GraceJobs/0.1"
  @whoishiring_url "https://hacker-news.firebaseio.com/v0/user/whoishiring.json"
  @item_url "https://hacker-news.firebaseio.com/v0/item/"

  @impl true
  def fetch(opts \\ []) do
    req = Keyword.get(opts, :req, &default_req/1)
    limit = Keyword.get(opts, :limit, 50)

    with {:ok, thread_id} <- find_thread_id(opts, req),
         {:ok, %{status: 200, body: body}} <- req.(item_url(thread_id)),
         kids when is_list(kids) <- body["kids"] do
      jobs =
        kids
        |> Enum.take(limit)
        |> Enum.map(fn id ->
          case req.(item_url(id)) do
            {:ok, %{status: 200, body: comment}} -> comment_to_raw(comment, thread_id)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, jobs}
    else
      {:ok, %{status: status}} -> {:error, {:bad_status, status}}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :no_thread}
    end
  end

  defp find_thread_id(opts, req) do
    case Keyword.get(opts, :thread_id) do
      nil ->
        with {:ok, %{status: 200, body: body}} <- req.(@whoishiring_url),
             ids when is_list(ids) <- body["submitted"],
             [first | _] <- ids do
          {:ok, first}
        else
          _ -> {:error, :no_thread}
        end

      id ->
        {:ok, id}
    end
  end

  defp item_url(id), do: @item_url <> "#{id}.json"

  defp default_req(url) do
    Req.get(url, headers: [{"user-agent", @user_agent}], retry: :transient)
  end

  defp comment_to_raw(%{"deleted" => true}, _), do: nil
  defp comment_to_raw(%{"dead" => true}, _), do: nil
  defp comment_to_raw(%{"text" => nil}, _), do: nil
  defp comment_to_raw(%{"text" => ""}, _), do: nil

  defp comment_to_raw(%{"id" => id, "text" => html} = c, thread_id) do
    text = strip_html(html)
    title = first_line(text)

    %{
      source: "hackernews",
      external_id: to_string(id),
      title: title || "HN Job",
      url: "https://news.ycombinator.com/item?id=#{id}",
      company: extract_company(title),
      description: text,
      remote: detect_remote(text),
      tags: [],
      posted_at: from_unix(c["time"]),
      raw: %{"id" => id, "thread_id" => thread_id}
    }
  end

  defp comment_to_raw(_, _), do: nil

  defp strip_html(nil), do: nil

  defp strip_html(html) do
    case Floki.parse_fragment(html) do
      {:ok, doc} -> doc |> Floki.text(sep: " ") |> String.trim()
      _ -> html
    end
  end

  defp first_line(nil), do: nil

  defp first_line(text) do
    text
    |> String.split(~r/[\.\|\-]/, parts: 2)
    |> List.first()
    |> String.trim()
    |> String.slice(0, 200)
  end

  defp extract_company(nil), do: nil

  defp extract_company(title) do
    case Regex.run(~r/^([A-Z][A-Za-z0-9 &.,'-]{1,40})\s+\|/, title) do
      [_, company] -> String.trim(company)
      _ -> nil
    end
  end

  defp detect_remote(text), do: String.contains?(String.downcase(text), "remote")

  defp from_unix(nil), do: nil

  defp from_unix(ts) when is_integer(ts) do
    case DateTime.from_unix(ts) do
      {:ok, dt} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end
