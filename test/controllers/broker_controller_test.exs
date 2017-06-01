defmodule Kastlex.BrokerControllerTest do
  use Kastlex.ConnCase
  require Logger

  setup do
    {:ok, path} = Briefly.create
    File.write(path, "test:\n  list_brokers: true\n")
    Application.put_env(:kastlex, :permissions_file_path, path)
    Kastlex.Users.reload
    {:ok, %{}}
  end

  test "lists all entries on index", _params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "test"})
    response = build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_broker_path(build_conn(), :list_brokers))
    |> json_response(200)

    assert is_list(response)
  end

  test "does not list all entries on index when permissions are not set", _params do
    build_conn()
    |> get(api_v1_broker_path(build_conn(), :list_brokers))
    |> json_response(403)
  end

end
