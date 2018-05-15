# http://elixir-recipes.github.io/concurrency/parallel-map/
defmodule Kastlex.Parallel do
  @timeout 5_000

  def pmap(collection, func) do
    pmap(collection, func, @timeout)
  end

  def pmap(collection, func, timeout) do
    collection
    |> Enum.map(&(Task.async(fn -> func.(&1) end)))
    |> Enum.map(fn(task) -> Task.await(task, timeout) end)
  end
end
