defmodule Oneiroi.Gaia.Error do
  @moduledoc "Identity's boundary failure vocabulary, built from its `errors/0`."
  # Derived rather than written, as `Oneiroi.SimaQian.Error` explains.
  use Oneiroi.Error, component: __MODULE__ |> Module.split() |> Enum.drop(-1) |> Module.concat()
end
