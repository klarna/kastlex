defmodule Kastlex.KafkaUtils do

  def parse_logical_offset("earliest"), do: -2
  def parse_logical_offset("latest"), do: -1
  def parse_logical_offset(n) do
    {offset, _} = Integer.parse(n)
    offset
  end

end
