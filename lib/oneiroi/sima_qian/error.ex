defmodule Oneiroi.SimaQian.Error do
  @moduledoc """
  Records' boundary failure vocabulary, built from its `errors/0`.

  The owning component is derived from `__MODULE__` rather than written
  `component: Oneiroi.SimaQian`: the system names `Backup` and `Rebuild`
  through its exports and its queue, both construct this struct, and the
  struct reads the system's `errors/0`, so the literal alias here closed
  a runtime cycle the cycles gate refuses. The derivation needs no name
  kept in step: an error module is always `<System>.Error`.
  """
  use Oneiroi.Error, component: __MODULE__ |> Module.split() |> Enum.drop(-1) |> Module.concat()
end
