defmodule Kastlex.Users do
  require Logger

  @table  :users
  @anon "anonymous"

  @server __MODULE__
  @reload :reload

  def start_link() do
    GenServer.start_link(__MODULE__, [], [name: @server])
  end

  def reload() do
    GenServer.call(@server, @reload)
  end

  def get_anonymous() do
    get_user(@anon)
  end

  def get_user(name) do
    case :ets.lookup(@table, name) do
      [] -> false
      [{_, user}] -> user
    end
  end

  def init(_options) do
    :ets.new(@table, [:set, :protected, :named_table, {:read_concurrency, true}])
    do_reload()
    {:ok, %{}}
  end

  def handle_call(@reload, _from, state) do
    do_reload()
    {:reply, :ok, state}
  end

  def handle_cast(cast, state) do
    Logger.error "Unexpected cast: #{cast}"
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.error "Unexpected msg: #{msg}"
    {:noreply, state}
  end

  def terminate(reason, _state) do
    Logger.info "#{inspect Kernel.self} is terminating: #{inspect reason}"
  end

  defp do_reload() do
    permissions_file_path = Application.fetch_env!(:kastlex, :permissions_file_path)
    Logger.info "Reloading permissions from #{permissions_file_path}"
    permissions = permissions_file_path
    |> YamlElixir.read_from_file
    |> validate_permissions
    passwd_file_path = Application.fetch_env!(:kastlex, :passwd_file_path)
    Logger.info "Reloading credentials from #{passwd_file_path}"
    passwd = passwd_file_path
    |> YamlElixir.read_from_file
    |> validate_passwd
    users = Map.merge(permissions, passwd, fn(_k, v1, v2) -> Map.merge(v1, v2) end) |>
      Enum.map(fn({k,v}) -> {k, map_keys_to_atoms(v) |> Keyword.put(:name, k)} end)
    :ets.delete_all_objects(@table)
    :ets.insert(@table, users)
  end

  defp validate_permissions(permissions), do: permissions

  defp validate_passwd(passwd), do: passwd

  defp map_keys_to_atoms(m) do
    Enum.map(m, fn({k,v}) -> {:erlang.binary_to_atom(k, :latin1), v} end)
  end

end

