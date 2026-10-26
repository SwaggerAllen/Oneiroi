defmodule Oneiroi.System do
  @moduledoc """
  What every system of spec §6 adopts (conventions §4):

      defmodule Oneiroi.Memory do
        use Oneiroi.System, slug: :memory
      end

  It is the substrate's component behaviour under the spec's own word:
  the substrate says "component" throughout, because it was written for
  a platform whose adopters are components, and renaming it would touch
  every module and test it ships with for a vocabulary gain alone. So
  "component" in a substrate message is a system here, and this macro is
  the one place the two words meet. It is also where the core will hang
  what the substrate does not know about: the permission check on
  `defexport` when identity lands, and nothing before then.

  The registries a system declares are the behaviour's callbacks:
  `config/0` (settings, with `usage:` and `tag:`), `processes/0`,
  `errors/0`, `externals/0`, `telemetry_events/0`, `events/0`,
  `oban_queues/0`, `pubsub_topics/0`, `policies/0`, `licensing/0`,
  `children/0`, `ready?/0`, `seeds/0`. Every one has an overridable empty
  default, and the composer fails the boot and the audit on a collision.
  """

  defmacro __using__(opts) do
    quote do
      use Oneiroi.Component, unquote(opts)
    end
  end
end
