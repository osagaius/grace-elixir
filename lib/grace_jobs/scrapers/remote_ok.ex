defmodule GraceJobs.Scrapers.RemoteOK do
  @moduledoc """
  Scrapes RemoteOK's public JSON feed at https://remoteok.com/api.

  RemoteOK requires a polite User-Agent. Their first record is metadata
  (a "legal" entry); subsequent entries are jobs.
  """
  @behaviour GraceJobs.Scrapers.Scraper

  @feed_url "https://remoteok.com/api"
  @user_agent "GraceJobs/0.1 (+https://github.com/osayame/grace-jobs)"

  @impl true
  def fetch(opts \\ []) do
    url = Keyword.get(opts, :url, @feed_url)
    req = Keyword.get(opts, :req, &default_req/1)

    case req.(url) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, body |> Enum.reject(&legal?/1) |> Enum.map(&to_raw/1)}

      {:ok, %{status: status}} ->
        {:error, {:bad_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_req(url) do
    case Req.get(url, headers: [{"user-agent", @user_agent}], retry: :transient) do
      {:ok, resp} -> {:ok, resp}
      {:error, e} -> {:error, e}
    end
  end

  defp legal?(%{"legal" => _}), do: true
  defp legal?(_), do: false

  defp to_raw(item) do
    %{
      source: "remoteok",
      external_id: to_string(item["id"] || item["slug"] || item["url"]),
      title: item["position"] || item["title"] || "Untitled",
      url: item["url"] || "https://remoteok.com/remote-jobs/#{item["id"]}",
      company: item["company"],
      description: strip_html(item["description"]),
      location: item["location"],
      remote: true,
      tags: List.wrap(item["tags"] || []) |> Enum.map(&to_string/1),
      posted_at: parse_date(item["date"]),
      raw: item
    }
  end

  defp strip_html(nil), do: nil

  defp strip_html(html) do
    case Floki.parse_fragment(html) do
      {:ok, doc} -> doc |> Floki.text() |> String.trim()
      _ -> html
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end
