defmodule Kastlex.ConsumerControllerTest do
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
                       "  show_group: all\n" <>
                       "  list_groups: true\n" <>
                       "wrong:\n" <>
                       "  list_brokers: true\n" <>
                       "not_exist:\n" <>
                       "  produce:\n" <>
                       "    - #{topic}\n" <>
                       "  show_group: all\n"
              )
    Application.put_env(:kastlex, :permissions_file_path, path)
    Kastlex.Users.reload
    {:ok, %{:topic => topic, :partition => partition}}
  end

  test "show chosen resource v2", params do
    {:ok, token, _} = Guardian.encode_and_sign(%{user: "test"})
    client_id = Kastlex.get_brod_client_id()
    group_id = "consumer-controller-tests-#{inspect :erlang.system_time()}"
    topic = params[:topic]
    partition = params[:partition]
    Kastlex.TestConsumer.start(client_id, topic, group_id)
    receive do
      :init -> :ok
    after
      5_000 -> assert false, "timeout"
    end
    :timer.sleep(10_000)
    {:ok, offset} = :brod.produce_sync_offset(client_id, topic, partition, "key", "foobar")
    receive do
      {"key", "foobar", ^offset} -> :ok
    after
      10_000 -> assert false, "timeout"
    end
    :timer.sleep(5_000)
    response = build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
    |> get(api_v2_consumer_path(build_conn(), :show_group, group_id))
    |> json_response(200)

    assert group_id == response["group_id"]
    assert "no_error" == response["error_code"]
    [t] = response["committed_offsets"]
    assert topic == t["topic"]
    [p] = t["partition_responses"]
    assert partition == p["partition"]
    assert offset+1 == p["offset"]
  end
end
