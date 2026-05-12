ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(GraceJobs.Repo, :manual)

# Mox stubs used across the suite
Mox.defmock(GraceJobs.ScraperMock, for: GraceJobs.Scrapers.Scraper)
Mox.defmock(GraceJobs.LLMMock, for: GraceJobs.LLM.Client)
