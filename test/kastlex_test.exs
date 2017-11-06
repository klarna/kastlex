defmodule KastlexTest do
  use ExUnit.Case, async: false

  import Mock

  test "get_brod_client_config empty env" do
    with_mock System, [:passthrough], [get_env: fn(_) -> nil end] do
      expected = [allow_topic_auto_creation: false,
                  auto_start_producers: true,
                  default_producer_config: [],
                  ssl: false,
                  sasl: :undefined
                 ]
      assert expected == Kastlex.get_brod_client_config
    end
  end

  test "get_brod_client_config ssl true" do
    f = fn("KASTLEX_KAFKA_USE_SSL") -> "true"
          (_) -> nil
    end
    with_mock System, [:passthrough], [get_env: f] do
      expected = [allow_topic_auto_creation: false,
                  auto_start_producers: true,
                  default_producer_config: [],
                  ssl: true,
                  sasl: :undefined
                 ]
      assert expected == Kastlex.get_brod_client_config
    end
  end

  test "get_brod_client_config ssl certs" do
    f = fn("KASTLEX_KAFKA_CACERTFILE") -> "foo"
          ("KASTLEX_KAFKA_CERTFILE") -> "foo"
          ("KASTLEX_KAFKA_KEYFILE") -> "foo"
          (_) -> nil
    end
    with_mock System, [:passthrough], [get_env: f] do
      expected = [allow_topic_auto_creation: false,
                  auto_start_producers: true,
                  default_producer_config: [],
                  ssl: [keyfile: "foo",
                        certfile: "foo",
                        cacertfile: "foo"],
                  sasl: :undefined
                 ]
      assert expected == Kastlex.get_brod_client_config
    end
  end

  test "get_brod_client_config producer config" do
    f = fn("KASTLEX_PRODUCER_REQUIRED_ACKS") -> "1"
          ("KASTLEX_PRODUCER_MAX_LINGER_COUNT") -> "2"
          (_) -> nil
    end
    with_mock System, [:passthrough], [get_env: f] do
      expected = [allow_topic_auto_creation: false,
                  auto_start_producers: true,
                  default_producer_config: [max_linger_count: 2,
                                            required_acks: 1],
                  ssl: false,
                  sasl: :undefined
                 ]
      assert expected == Kastlex.get_brod_client_config
    end
  end

  test "get_brod_client_config producer config sasl" do
    f1 = fn("KASTLEX_KAFKA_SASL_FILE") -> "foobar.yaml"
           (_) -> nil
    end
    f2 = fn("foobar.yaml") -> %{"username" => "foo", "password" => "bar"}
           (_) -> nil
    end
    with_mocks [{System, [:passthrough], [get_env: f1]},
                {YamlElixir, [:passthrough], [read_from_file: f2]}] do
      expected = [allow_topic_auto_creation: false,
                  auto_start_producers: true,
                  default_producer_config: [],
                  ssl: false,
                  sasl: {:plain, 'foo', 'bar'}
                 ]
      assert expected == Kastlex.get_brod_client_config
    end
  end
end
