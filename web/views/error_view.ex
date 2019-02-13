defmodule Kastlex.ErrorView do
  use Kastlex.Web, :view

  def render("404.json", _assings) do
    %{error: "Not found"}
  end

  def render("404.html", _assigns) do
    {:safe, Jason.encode!(%{error: "No route"})}
  end

  def render("500.json", _assigns) do
    %{error: "Internal server error"}
  end

  # In case no render clause matches or no
  # template is found, let's render it as 500
  def template_not_found(_template, assigns) do
    render "500.json", assigns
  end
end
