defmodule Oneiroi.Xenia.RoutesLedger do
  @moduledoc """
  A resident's own routes and their runs (xenia#19), on
  `routes-<resident_id>`. Either party defines one or asks a run, the
  descriptor checked against the safe subset before it gets here; the
  reader (the hands) or the witness says a run landed or failed. A run
  is numbered by the stream, and lands or fails once.
  """

  alias Oneiroi.Xenia.Commands
  alias Oneiroi.Xenia.Error
  alias Oneiroi.Xenia.Events

  @parties [:resident, :witness]
  @deliverers [:hands, :witness]

  defstruct routes: MapSet.new(), runs: %{}, next: 1

  def execute(%__MODULE__{}, %Commands.DefineRoute{actor: %{kind: k}}) when k not in @parties,
    do: {:error, Error.new(:xenia_not_allowed, :xenia_routes_ledger_define_party)}

  def execute(%__MODULE__{routes: routes}, %Commands.DefineRoute{} = c) do
    module = if MapSet.member?(routes, c.key), do: Events.RouteChanged, else: Events.RouteDefined

    struct!(module,
      actor: c.actor,
      at: c.at,
      id: c.id,
      key: c.key,
      descriptor: c.descriptor,
      note: c.note
    )
  end

  def execute(%__MODULE__{}, %Commands.AskRoute{actor: %{kind: k}}) when k not in @parties,
    do: {:error, Error.new(:xenia_not_allowed, :xenia_routes_ledger_ask_party)}

  def execute(%__MODULE__{} = s, %Commands.AskRoute{} = c) do
    if MapSet.member?(s.routes, c.key),
      do: %Events.RouteAsked{
        actor: c.actor,
        at: c.at,
        id: c.id,
        key: c.key,
        number: s.next,
        note: c.note
      },
      else: {:error, Error.new(:xenia_no_such_route, :xenia_routes_ledger_ask_none)}
  end

  def execute(%__MODULE__{}, %{actor: %{kind: k}} = c)
      when k not in @deliverers and is_struct(c, Commands.LandRoute)
      when k not in @deliverers and is_struct(c, Commands.FailRoute),
      do: {:error, Error.new(:xenia_not_allowed, :xenia_routes_ledger_deliver_party)}

  def execute(%__MODULE__{runs: runs}, %Commands.LandRoute{} = c) do
    case Map.get(runs, c.number) do
      :open ->
        %Events.RouteLanded{actor: c.actor, at: c.at, id: c.id, number: c.number, path: c.path}

      _done_or_none ->
        {:error, Error.new(:xenia_no_such_route, :xenia_routes_ledger_land_none)}
    end
  end

  def execute(%__MODULE__{runs: runs}, %Commands.FailRoute{} = c) do
    case Map.get(runs, c.number) do
      :open ->
        %Events.RouteFailed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          reason: c.reason
        }

      _done_or_none ->
        {:error, Error.new(:xenia_no_such_route, :xenia_routes_ledger_fail_none)}
    end
  end

  def apply(%__MODULE__{} = s, %Events.RouteDefined{key: k}),
    do: %{s | routes: MapSet.put(s.routes, k)}

  def apply(%__MODULE__{} = s, %Events.RouteChanged{}), do: s

  def apply(%__MODULE__{} = s, %Events.RouteAsked{number: n}),
    do: %{s | next: n + 1, runs: Map.put(s.runs, n, :open)}

  def apply(%__MODULE__{} = s, %Events.RouteLanded{number: n}),
    do: %{s | runs: Map.put(s.runs, n, :landed)}

  def apply(%__MODULE__{} = s, %Events.RouteFailed{number: n}),
    do: %{s | runs: Map.put(s.runs, n, :failed)}
end
