defmodule GraceJobsWeb.PageController do
  use GraceJobsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
