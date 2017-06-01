defmodule Kastlex.MessageControllerTest do
  use Kastlex.ConnCase

  setup do
    {:ok, path} = Briefly.create
    topic = "kastlex"
    partition = 0
    File.write(path, "test:\n" <>
                       "  fetch:\n" <>
                       "    - #{topic}\n" <>
                       "  produce:\n" <>
                       "    - #{topic}\n" <>
                       "wrong:\n" <>
                       "  list_brokers: true\n" <>
                       "not_exist:\n" <>
                       "  fetch: all\n" <>
                       "  produce: all\n" <>
                       "wrong_topic:\n" <>
                       "  fetch:\n" <>
                       "    - wrong_topic\n" <>
                       "  produce:\n" <>
                       "    - wrong_topic\n"
              )
    Application.put_env(:kastlex, :permissions_file_path, path)
    Kastlex.Users.reload
    # ensure we have a message to test on
    :brod.produce_sync(Kastlex.get_brod_client_id(), topic, partition, "", "test")
    {:ok, %{:topic => topic, :partition => partition}}
  end

  test "show chosen resource", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "test"})
    response = build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_message_path(build_conn(), :fetch, params[:topic], params[:partition]))
    |> json_response(200)

    assert Kernel.is_map(response)
  end

  test "show chosen resource when accepting binary", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "test"})
    response = build_conn()
    |> put_req_header("accept", "application/binary")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_message_path(build_conn(), :fetch, params[:topic], params[:partition]))
    |> response(200)

    assert response == "test"
  end

  test "does not show resource when permissions are not set", params do
    response = build_conn()
    |> put_req_header("accept", "application/json")
    |> get(api_v1_message_path(build_conn(), :fetch, params[:topic], params[:partition]))
    |> json_response(403)

    assert Kernel.is_map(response)
  end

  test "does not show resource with wrong permissions", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "wrong"})
    response = build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_message_path(build_conn(), :fetch, params[:topic], params[:partition]))
    |> json_response(403)

    assert Kernel.is_map(response)
  end

  test "does not show resource with wrong resource permissions", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "wrong_topic"})
    response = build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_message_path(build_conn(), :fetch, params[:topic], params[:partition]))
    |> json_response(403)

    assert Kernel.is_map(response)
  end

  test "returns 404 when resource does not exist", _params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "not_exist"})
    response = build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_message_path(build_conn(), :fetch, "not_exist", 0))
    |> json_response(404)

    assert Kernel.is_map(response)
  end

  test "creates resource", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "test"})
    build_conn()
    |> put_req_header("content-type", "application/binary")
    |> put_req_header("authorization", "Bearer #{token}")
    |> post(api_v1_message_path(build_conn(), :produce, params[:topic]), "test")
    |> response(204)

  end

  test "does not create resource when permissions are not set", params do
    build_conn()
    |> put_req_header("content-type", "application/binary")
    |> post(api_v1_message_path(build_conn(), :produce, params[:topic]), "test")
    |> response(403)
  end

  test "does not create resource with wrong permissions", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "wrong"})
    build_conn()
    |> put_req_header("content-type", "application/binary")
    |> put_req_header("authorization", "Bearer #{token}")
    |> post(api_v1_message_path(build_conn(), :produce, params[:topic]), "test")
    |> response(403)
  end

  test "does not create resource with wrong resource permissions", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "wrong_topic"})
    build_conn()
    |> put_req_header("content-type", "application/binary")
    |> put_req_header("authorization", "Bearer #{token}")
    |> post(api_v1_message_path(build_conn(), :produce, params[:topic]), "test")
    |> response(403)
  end

  test "returns 404 on POST when resource does not exist", _params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "not_exist"})
    build_conn()
    |> put_req_header("content-type", "application/binary")
    |> put_req_header("authorization", "Bearer #{token}")
    |> post(api_v1_message_path(build_conn(), :produce, "not_exist"), "test")
    |> response(404)
  end
end
