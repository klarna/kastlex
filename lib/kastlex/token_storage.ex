defmodule Kastlex.TokenStorage do

  require Logger
  require Record

  use GenServer
  use Guardian.Hooks

  import Record, only: [defrecord: 2, extract: 2]

  defrecord :kafka_message_set, extract(:kafka_message_set, from_lib: "brod/include/brod.hrl")
  defrecord :kafka_fetch_error, extract(:kafka_fetch_error, from_lib: "brod/include/brod.hrl")
  defrecord :kafka_message, extract(:kafka_message, from_lib: "brod/include/brod.hrl")

  config = Application.get_env(:kastlex, Kastlex.TokenStorage, [])
  @topic Keyword.get(config, :topic)

  if length(config) == 0, do: raise "Kastlex.TokenStorage configuration is required"
  if is_nil(@topic), do: raise "Kastlex.TokenStorage requires a topic"

  @server __MODULE__
  @resubscribe_delay 10_000

  # ets tables
  @tokens_table :tokens # ets table for tokens

  def after_encode_and_sign(resource, type, claims, jwt) do
    case register(claims["sub"], token_hash(jwt), claims["exp"]) do
      {:error, _} -> {:error, :token_storage_failure}
      _           -> {:ok, {resource, type, claims, jwt}}
    end
  end

  def on_verify(claims, jwt) do
    hash = token_hash(jwt)
    case :ets.lookup(@tokens_table, claims["sub"]) do
      [{_, %{token_hash:  ^hash}}] ->
        {:ok, {claims, jwt}}
      _ ->
        {:error, :token_not_found}
    end
  end

  def on_revoke(claims, jwt) do
    case revoke(claims["sub"]) do
      :ok         -> {:ok, {claims, jwt}}
      {:error, _} -> {:error, :could_not_revoke_token}
    end
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: @server)
  end

  def register(sub, token_hash, exp) do
    GenServer.call(@server, {:register, sub, token_hash, exp})
  end

  def revoke(sub) do
    GenServer.call(@server, {:revoke, sub})
  end

  def init(options) do
    case Kastlex.token_storage_enabled? do
      true -> do_init(options)
      false ->
        Logger.info "Token storage is disabled"
        :ignore
    end
  end

  defp do_init(_options) do
    :ets.new(@tokens_table, [:set, :protected, :named_table, {:read_concurrency, true}])
    client = Kastlex.get_brod_client_id
    :ok = :brod.start_consumer(client, @topic, [])
    :ok = :brod.start_producer(client, @topic, [])
    send self, :subscribe
    {:ok, %{:client => client}}
  end

  def handle_call({:register, sub, token_hash, exp}, _from, state) do
    data = :erlang.term_to_binary(%{:token_hash => token_hash, :exp => exp})
    case :brod.produce_sync(state.client, @topic, 0, sub, data) do
      :ok ->
        :ets.insert(@tokens_table, {sub, data})
        Logger.debug "successfully registered token for #{sub}"
        {:reply, :ok, state}
      {:error, _} = error ->
        Logger.error "failed to send token to kafka: #{inspect error}"
        {:reply, error, state}
    end
  end

  def handle_call({:revoke, sub}, _from, state) do
    case :brod.produce_sync(state.client, @topic, 0, sub, "") do
      :ok ->
        :ets.delete(@tokens_table, sub)
        Logger.debug "successfully deleted token for #{sub}"
        {:reply, :ok, state}
      {:error, _} = error ->
        Logger.error "failed to delete token from kafka: #{inspect error}"
        {:reply, error, state}
    end
  end

  def handle_info(:subscribe, state) do
    options = [{:begin_offset, :earliest},
               {:prefetch_count, 1_000}
              ]
    case :brod.subscribe(state.client, self(), @topic, 0, options) do
      {:ok, pid} ->
        Logger.info "subscribed on #{@topic}"
        _ = Process.monitor(pid)
        {:noreply, Map.put(state, :consumer, pid)}
      {:error, reason} ->
        Logger.error "failed to subscribe on #{@topic}: #{inspect reason}"
        # consumer down, client down, etc. try again later
        resubscribe()
        {:noreply, state}
    end
  end

  def handle_info({pid, msg_set}, %{consumer: pid} = state)
  when Record.is_record(msg_set, :kafka_message_set) do
    messages = kafka_message_set(msg_set, :messages)
    last_offset = kafka_message(List.last(messages), :offset)
    Enum.each(messages, fn(msg) -> handle_message(msg) end)
    :ok = :brod.consume_ack(pid, last_offset)
    {:noreply, state}
  end

  def handle_info({pid, fetch_error}, %{consumer: pid} = state)
  when Record.is_record(fetch_error, :kafka_fetch_error) do
    Logger.info "fetch error: #{inspect fetch_error}"
    resubscribe()
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{consumer: pid} = state) do
    Logger.info "consumer process died: #{inspect reason}"
    resubscribe()
    {:noreply, state}
  end

  defp handle_message(msg) do
    key = kafka_message(msg, :key)
    value = kafka_message(msg, :value)
    # allow different definitions of 'null'
    case value do
      :undefined ->
        :ets.delete(@tokens_table, key)
      "" ->
        :ets.delete(@tokens_table, key)
      nil ->
        :ets.delete(@tokens_table, key)
      _ ->
        :ets.insert(@tokens_table, {key, :erlang.binary_to_term(value)})
    end
  end

  defp resubscribe() do
    Process.send_after self, :subscribe, @resubscribe_delay
  end

  defp token_hash(jwt) do
    :crypto.hash(:sha256, jwt)
  end

end
