defmodule Oneiroi.AgathosDaimon.PluginsRouter do
  @moduledoc "The plugins aggregate's router (agathos-daimon#37): `plugins-<resident_id>`."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.AgathosDaimon.PluginLedger",
    prefix: "plugins-",
    commands: "Oneiroi.AgathosDaimon.Commands",
    dispatching: ~w(ProposePlugin AnswerPlugin SwitchPluginOff CarryOverPlugins)
end
