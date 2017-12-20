defmodule Kastlex.MetricsControllerTest do
  use Kastlex.ConnCase


  test "show chosen resource", _params do
    build_conn()
    |> get(metrics_path(build_conn(), :fetch))
    |> response(200)
  end
end
