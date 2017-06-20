defmodule Kastlex.Router do
  require Logger

  use Kastlex.Web, :router
  use Plug.ErrorHandler

  import Kastlex.Helper

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json", "binary"]
    plug Kastlex.Accept
  end

  pipeline :auth do
    plug Guardian.Plug.VerifyHeader, realm: "Bearer"
    plug Guardian.Plug.LoadResource
    plug Kastlex.Plug.EnsureAuthenticated
  end

  scope "/", Kastlex do
    pipe_through :browser # Use the default browser stack
    get "/", PageController, :index
  end

  scope "/", Kastlex do
    pipe_through :api
    post "/login", LoginController, :login
    #get "/favicon.ico", CatchAllController, :favicon
  end

  scope "/admin", as: :admin, alias: Kastlex.Admin do
    pipe_through [:api, :auth]
    get "/reload", AdminController, :reload
    delete "/tokens/:username", AdminController, :revoke
  end

  scope "/api/v1", as: :api_v1, alias: Kastlex.API.V1 do
    pipe_through [:api, :auth]
    get  "/topics", TopicController, :list_topics
    get  "/topics/:topic", TopicController, :show_topic
    get  "/brokers", BrokerController, :list_brokers
    get  "/brokers/:broker", BrokerController, :show_broker
    get  "/offsets/:topic/:partition", OffsetController, :show_offsets
    post "/messages/:topic", MessageController, :produce
    post "/messages/:topic/:partition", MessageController, :produce
    get  "/messages/:topic/:partition", MessageController, :fetch
    get  "/messages/:topic/:partition/:offset", MessageController, :fetch
    get  "/urp", UrpController, :list_urps
    get  "/urp/:topic", UrpController, :show_urps
    get  "/consumers", ConsumerController, :list_groups
    get  "/consumers/:group_id", ConsumerController, :show_group
  end

  def handle_errors(conn, data) do
    Logger.error "#{inspect data}"
    send_json(conn, conn.status, %{error: "Something went wrong"})
  end

end
