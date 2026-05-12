defmodule GraceJobs.Scrapers.RemoteOKTest do
  use ExUnit.Case, async: true
  alias GraceJobs.Scrapers.RemoteOK

  test "skips legal record and maps fields" do
    payload = [
      %{"legal" => "policy"},
      %{
        "id" => "abc",
        "position" => "Senior TypeScript Engineer",
        "company" => "Acme",
        "url" => "https://remoteok.com/jobs/abc",
        "description" => "<p>Build cool stuff.</p>",
        "location" => "Remote",
        "tags" => ["typescript", "react"],
        "date" => "2026-05-09T10:00:00+00:00"
      }
    ]

    fake_req = fn _url -> {:ok, %{status: 200, body: payload}} end

    assert {:ok, [job]} = RemoteOK.fetch(req: fake_req)
    assert job.source == "remoteok"
    assert job.external_id == "abc"
    assert job.title == "Senior TypeScript Engineer"
    assert job.company == "Acme"
    assert job.url == "https://remoteok.com/jobs/abc"
    assert job.description == "Build cool stuff."
    assert job.tags == ["typescript", "react"]
    assert %DateTime{} = job.posted_at
  end

  test "propagates non-200 as error" do
    req = fn _ -> {:ok, %{status: 503, body: "down"}} end
    assert {:error, {:bad_status, 503}} = RemoteOK.fetch(req: req)
  end

  test "propagates transport errors" do
    req = fn _ -> {:error, :timeout} end
    assert {:error, :timeout} = RemoteOK.fetch(req: req)
  end
end
