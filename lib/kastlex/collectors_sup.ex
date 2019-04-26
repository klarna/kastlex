defmodule Kastlex.Collectors do
  @behaviour :supervisor3

  def start_link() do
    :supervisor3.start_link({:local, __MODULE__}, __MODULE__, [])
  end

  def init(_options) do
    :ok = Kastlex.CgCache.init()
    children =
      [ child_spec(Kastlex.MetadataCache, []),
        child_spec(Kastlex.OffsetsCache, []),
        child_spec(Kastlex.CgStatusCollector, [])
      ]
    {:ok, {{:one_for_one, 0, 1}, children}}
  end

  def post_init(_) do
    # Force brod client to connect to all brokers in the cluster
    # so that we get faster response when users request consumer group status.
    # This call requires brod client and metadata cache to be up
    Kastlex.CgLib.init_connections()
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
