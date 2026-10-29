defmodule OneiroiWeb.ChannelCase do
  @moduledoc """
  The case for tests that drive a channel in process. The sandbox is the
  test's to check out, shared, as `OneiroiWeb.ContractTest` does: the
  brain's session process writes from its own process, and this module
  is compiled inside the web boundary, which does not reach Ecto.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import OneiroiWeb.ChannelCase

      @endpoint OneiroiWeb.Endpoint
    end
  end
end
