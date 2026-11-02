defmodule Oneiroi.Kumbukumbu.Kinds do
  @moduledoc """
  The one rule for which kind a session opened through an adapter is
  (kumbukumbu #40), in a module of its own because two readers need it
  and one of them is the event's upcaster: the aggregate refers to the
  events' structs, so the upcaster calling back into the aggregate would
  be a cycle.
  """

  # The platform's own loop names itself as this adapter (spec §8), and
  # only its sessions may be of kind `main`: the Oneiroi chat is the
  # canonical conversation and every other runtime is secondary to it
  # (the author: "Only the Oneiroi chat should be the canonical, Claude
  # is a secondary platform").
  @platform "brain"
  @adapter "adapter"

  @doc "The adapter name the platform's own loop opens its sessions under."
  @spec platform() :: String.t()
  def platform, do: @platform

  @doc "The kind of a session another runtime's adapter opened."
  @spec adapter() :: String.t()
  def adapter, do: @adapter

  @doc """
  The kind a session opened as `kind` through `adapter` is: `main`
  through any adapter but the platform's own is `adapter`, every other
  pair is itself. The command edge and the upcaster both read it, so a
  session an adapter opened as `main` before the rule, read back from
  the log, is what one opened now is.
  """
  @spec kind_for(String.t() | nil, String.t() | nil) :: String.t() | nil
  def kind_for("main", adapter) when adapter != @platform, do: @adapter
  def kind_for(kind, _adapter), do: kind
end
