defmodule GraceJobs.Scrapers.WeWorkRemotelyTest do
  use ExUnit.Case, async: true
  alias GraceJobs.Scrapers.WeWorkRemotely

  @rss """
  <?xml version="1.0"?>
  <rss><channel>
    <item>
      <title>Acme Corp: Senior Python Engineer</title>
      <link>https://weworkremotely.com/remote-jobs/acme-1</link>
      <guid>wwr-1</guid>
      <description><![CDATA[<p>Python &amp; Django.</p>]]></description>
      <pubDate>Fri, 09 May 2026 12:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Lone Title</title>
      <link>https://weworkremotely.com/remote-jobs/solo-2</link>
      <guid>wwr-2</guid>
      <description><![CDATA[]]></description>
      <pubDate>Fri, 09 May 2026 12:01:00 +0000</pubDate>
    </item>
  </channel></rss>
  """

  test "parses items, splits company/title, normalises dates" do
    req = fn _url -> {:ok, %{status: 200, body: @rss}} end
    assert {:ok, [first, second]} = WeWorkRemotely.fetch(req: req)
    assert first.source == "weworkremotely"
    assert first.company == "Acme Corp"
    assert first.title == "Senior Python Engineer"
    assert first.external_id == "wwr-1"
    assert %DateTime{} = first.posted_at
    assert second.company == nil
    assert second.title == "Lone Title"
  end

  test "returns error on bad status" do
    req = fn _ -> {:ok, %{status: 500, body: "boom"}} end
    assert {:error, {:bad_status, 500}} = WeWorkRemotely.fetch(req: req)
  end
end
