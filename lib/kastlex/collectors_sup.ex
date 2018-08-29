defmodule Kastlex.Collectors do
  @behaviour :supervisor3

  def start_link() do
    :supervisor3.start_link({:local, __MODULE__}, __MODULE__, [])
  end

  def init(_options) do
    zk_cluster = Kastlex.get_zk_cluster
    client_id = Kastlex.get_brod_client_id
    children =
      [ child_spec(Kastlex.MetadataCache, [%{zk_cluster: zk_cluster}]),
        child_spec(Kastlex.OffsetsCache, [%{}]),
        child_spec(Kastlex.CgStatusCollector, [%{brod_client_id: client_id}])
      ]
    {:ok, {{:one_for_one, 0, 1}, children}}
  end

  def post_init(_) do
    :ignore
  end

  defp child_spec(mod, start_args) do
    {mod,
     {mod, :start_link, start_args},
     {:permanent, 30},
     5000,
     :worker,
     [mod]}
  end
end
