defmodule GraceJobs.Scrapers.HackerNewsTest do
  use ExUnit.Case, async: true
  alias GraceJobs.Scrapers.HackerNews

  test "fetches thread, then maps comments" do
    thread = %{"kids" => [101, 102]}

    c1 = %{
      "id" => 101,
      "text" => "Acme | Senior Kubernetes Engineer | Remote | We do Go.",
      "time" => 1_715_000_000
    }

    c2 = %{
      "id" => 102,
      "deleted" => true
    }

    req = fn url ->
      cond do
        String.contains?(url, "item/1.json") -> {:ok, %{status: 200, body: thread}}
        String.contains?(url, "item/101") -> {:ok, %{status: 200, body: c1}}
        String.contains?(url, "item/102") -> {:ok, %{status: 200, body: c2}}
        true -> {:error, :unexpected_url}
      end
    end

    assert {:ok, [job]} = HackerNews.fetch(thread_id: 1, req: req)
    assert job.source == "hackernews"
    assert job.external_id == "101"
    assert job.url == "https://news.ycombinator.com/item?id=101"
    assert job.remote == true
  end

  test "returns error when thread cannot be resolved" do
    req = fn _ -> {:ok, %{status: 200, body: %{"submitted" => []}}} end
    assert {:error, _} = HackerNews.fetch(req: req)
  end
end
