defmodule OneiroiWeb.ConnCase do
  @moduledoc "The case for tests that drive the endpoint in process."
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint OneiroiWeb.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
      import OneiroiWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
