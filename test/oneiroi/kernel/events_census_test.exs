defmodule Oneiroi.EventsCensusTest do
  @moduledoc """
  Every event module a system compiles is in that system's `events/0`, at
  the version the module declares, and nothing in `events/0` is not an
  event. The registry is what the audit and the fixture test read, so a
  module missing from it is a shape nothing guards (conventions §6).
  """
  use ExUnit.Case, async: true

  alias Oneiroi.Event.Codec

  @systems Application.compile_env!(:oneiroi, :components)

  test "events/0 is the census of each system's event modules" do
    {:ok, modules} = :application.get_key(:oneiroi, :modules)

    for system <- @systems do
      prefix = Atom.to_string(system) <> ".Events."

      compiled =
        for module <- modules,
            String.starts_with?(Atom.to_string(module), prefix),
            Codec.event_module?(module),
            into: %{},
            do: {module, module.__version__()}

      declared = Map.new(system.events())

      for {module, _} <- declared do
        assert Codec.event_module?(module),
               "#{inspect(module)} is declared but is not an event"
      end

      assert declared == compiled,
             "#{inspect(system)}.events/0 differs from its compiled event modules: " <>
               inspect(declared: declared, compiled: compiled)
    end
  end
end
