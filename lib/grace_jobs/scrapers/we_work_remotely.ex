defmodule GraceJobs.Scrapers.WeWorkRemotely do
  @moduledoc """
  Scrapes WeWorkRemotely RSS feeds. Default: programming category.
  https://weworkremotely.com/categories/remote-programming-jobs.rss
  """
  @behaviour GraceJobs.Scrapers.Scraper

  @feed_url "https://weworkremotely.com/categories/remote-programming-jobs.rss"
  @user_agent "GraceJobs/0.1 (+https://github.com/osayame/grace-jobs)"

  @impl true
  def fetch(opts \\ []) do
    url = Keyword.get(opts, :url, @feed_url)
    req = Keyword.get(opts, :req, &default_req/1)

    with {:ok, %{status: 200, body: body}} <- req.(url),
         {:ok, parsed} <- parse_rss(body) do
      {:ok, parsed}
    else
      {:ok, %{status: status}} -> {:error, {:bad_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_req(url) do
    Req.get(url, headers: [{"user-agent", @user_agent}], retry: :transient)
  end

  defp parse_rss(xml) do
    with {:ok, doc} <- Floki.parse_document(xml) do
      items =
        doc
        |> Floki.find("item")
        |> Enum.map(&item_to_raw/1)
        |> Enum.reject(&is_nil/1)

      {:ok, items}
    end
  end

  defp item_to_raw(item) do
    title = item |> Floki.find("title") |> Floki.text() |> String.trim()
    link = item |> Floki.find("link") |> Floki.text() |> String.trim()
    desc = item |> Floki.find("description") |> Floki.text()
    pub_date = item |> Floki.find("pubdate, pubDate") |> Floki.text() |> String.trim()
    guid = item |> Floki.find("guid") |> Floki.text() |> String.trim()

    if title == "" or link == "" do
      nil
    else
      {company, role_title} = split_title(title)

      %{
        source: "weworkremotely",
        external_id: if(guid != "", do: guid, else: link),
        title: role_title,
        company: company,
        url: link,
        description: desc |> Floki.parse_fragment!() |> Floki.text() |> String.trim(),
        remote: true,
        tags: [],
        posted_at: parse_rss_date(pub_date),
        raw: %{"title" => title, "link" => link, "guid" => guid, "pubDate" => pub_date}
      }
    end
  end

  defp split_title(title) do
    case String.split(title, ":", parts: 2) do
      [company, rest] -> {String.trim(company), String.trim(rest)}
      [_] -> {nil, title}
    end
  end

  defp parse_rss_date(""), do: nil

  defp parse_rss_date(s) do
    # RFC2822-ish — "Mon, 09 May 2026 14:32:00 +0000"
    re = ~r/(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s*([+-]\d{4})?/

    case Regex.run(re, s) do
      [_, d, mon, y, h, mi, sec | _rest] ->
        with {:ok, date} <- Date.new(String.to_integer(y), month_index(mon), String.to_integer(d)),
             {:ok, time} <-
               Time.new(String.to_integer(h), String.to_integer(mi), String.to_integer(sec)),
             {:ok, dt} <- DateTime.new(date, time, "Etc/UTC") do
          DateTime.truncate(dt, :second)
        else
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  defp month_index(m), do: Enum.find_index(@months, &(&1 == m)) |> Kernel.+(1)
end
