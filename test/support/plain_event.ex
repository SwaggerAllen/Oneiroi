defmodule Oneiroi.Test.PlainEvent do
  @moduledoc "An event with one field, for the kernel's own tests; compiled with the app so its encoder consolidates."
  use Oneiroi.Event, version: 1, fields: [:name]
end
