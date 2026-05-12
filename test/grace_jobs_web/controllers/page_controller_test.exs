defmodule GraceJobsWeb.PageControllerTest do
  use GraceJobsWeb.ConnCase

  test "GET /about renders the Phoenix marketing page", %{conn: conn} do
    conn = get(conn, ~p"/about")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end
end
