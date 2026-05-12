# Linkbot & Grace Jobs

This repository consolidates the Linkbot application (Claude session runner) and the Grace Jobs application (harvesters and job pipeline).

## Applications

* **Linkbot** (Port 4050): Phoenix LiveView dashboard for running Claude sessions that apply to LinkedIn jobs.
* **Grace Jobs** (Port 4000): Phoenix LiveView dashboard for harvesting and classifying jobs from various sources.

Both applications share the same Postgres database (`grace_jobs_dev`).

## Getting Started

* Run `mix setup` to install and setup dependencies for both components.
* Start the consolidated Phoenix server with `mix phx.server`. Both endpoints will boot.

Now you can visit:
* [`localhost:4050`](http://localhost:4050) for Linkbot.
* [`localhost:4000`](http://localhost:4000) for Grace Jobs (also mapped to `/grace` on port 4050).
