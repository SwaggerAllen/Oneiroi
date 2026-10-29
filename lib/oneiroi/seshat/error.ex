defmodule Oneiroi.Seshat.Error do
  @moduledoc "The library's boundary failure vocabulary, built from its `errors/0`."
  use Oneiroi.Error, component: __MODULE__ |> Module.split() |> Enum.drop(-1) |> Module.concat()
end
