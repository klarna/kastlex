defmodule Kastlex.Router do
  use Kastlex.Web, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", Kastlex do
    pipe_through :api

    scope "/api/v1", as: :api_v1, alias: API.V1 do
      resources "/topics", TopicController, param: "topic", only: [:index, :show]
    end
  end
end
