defmodule Oneiroi.Apsu.Error do
  @moduledoc """
  The platform system's boundary failure vocabulary, built from its
  `errors/0`. The component is derived from `__MODULE__`, as every
  system's is (`Oneiroi.SimaQian.Error` has the reason: a literal alias
  closes a runtime cycle).
  """
  use Oneiroi.Error, component: __MODULE__ |> Module.split() |> Enum.drop(-1) |> Module.concat()
end
