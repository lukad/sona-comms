defmodule SonaCommsWeb.PageController do
  use SonaCommsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
