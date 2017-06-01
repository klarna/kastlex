defmodule Kastlex.TopicControllerTest do
  use Kastlex.ConnCase

  setup do
    {:ok, path} = Briefly.create
    topic = "kastlex"
    File.write(path, "test:\n" <>
                       "  list_topics: true\n" <>
                       "  show_topic:\n" <>
                       "    - #{topic}\n" <>
                       "wrong:\n" <>
                       "  list_brokers: true\n" <>
                       "wrong_topic:\n" <>
                       "  show_topic:\n" <>
                       "    - some-other-topic\n"
              )
    Application.put_env(:kastlex, :permissions_file_path, path)
    Kastlex.Users.reload
    {:ok, %{:topic => topic}}
  end

  test "lists all entries on index", _params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "test"})
    response = build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_topic_path(build_conn(), :list_topics))
    |> json_response(200)

    assert is_list(response)
  end

  test "does not list all entries on index when permissions are not set", _params do
    build_conn()
    |> get(api_v1_topic_path(build_conn(), :list_topics))
    |> json_response(403)
  end

  test "does not list all entries on index with wrong permissions", _params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "wrong"})
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_topic_path(build_conn(), :list_topics))
    |> json_response(403)
  end

  test "show chosen resource", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "test"})
    response = build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_topic_path(build_conn(), :show_topic, params.topic))
    |> json_response(200)
    assert response["topic"] == params.topic
  end

  test "does not show resource when permissions are wrong", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "wrong"})
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_topic_path(build_conn(), :show_topic, params.topic))
    |> json_response(403)
  end

  test "does not show resource when permissions are not set", params do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> get(api_v1_topic_path(build_conn(), :show_topic, params.topic))
    |> json_response(403)
  end

  test "does not show resource when it is not listed in subject", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "wrong_topic"})
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v1_topic_path(build_conn(), :show_topic, params.topic))
    |> json_response(403)
  end

end
