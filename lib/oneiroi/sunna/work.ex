defmodule Oneiroi.Sunna.Work do
  @moduledoc """
  The work queue aggregate (sunna#33), on `work-<resident_id>`: long,
  multi-turn items in priority order, the resident's and her witness's
  alike, numbered from 1. Either party adds an item, moves its status
  with a note, or reorders the list; the loop runs one item at a time
  (`StartWork` claims it, so two checks cannot start two), the resident
  wraps the run (what shipped, what slipped, why), and the run's end
  frees the loop for the next. When nothing can run, the loop rests and
  says why, once per reason: "empty, holding" is a state.

  Statuses: `open`, `in_work` (the loop's alone: the item running now),
  `blocked` (with what blocks it named), `done`, `dropped`.
  """

  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Events

  defstruct next: 1, items: %{}, order: [], running: nil, wrapped: false, rested: nil

  @parties [:resident, :witness]
  @moved ~w(open blocked done dropped)
  @wrapped ~w(open blocked done)
  @what 300
  @words 4_000

  def execute(%__MODULE__{next: n}, %Commands.AddWork{} = c) do
    cond do
      c.actor.kind not in @parties ->
        {:error, Error.new(:sunna_work_not_a_party, :sunna_work_add_not_a_party)}

      not words?(c.what, @what) or not words?(c.done_when, @words) ->
        {:error, Error.new(:sunna_work_invalid, :sunna_work_add_invalid)}

      true ->
        %Events.WorkAdded{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: n,
          what: String.trim(c.what),
          done_when: String.trim(c.done_when)
        }
    end
  end

  def execute(%__MODULE__{items: items}, %Commands.MoveWork{} = c) do
    cond do
      c.actor.kind not in @parties ->
        {:error, Error.new(:sunna_work_not_a_party, :sunna_work_move_not_a_party)}

      not Map.has_key?(items, c.number) ->
        {:error, Error.new(:sunna_no_such_work, :sunna_work_move_unknown)}

      not status_ok?(c.status, c.blocked_on, @moved) or not words?(c.note, @words) ->
        {:error, Error.new(:sunna_work_invalid, :sunna_work_move_invalid)}

      true ->
        %Events.WorkMoved{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          status: c.status,
          blocked_on: blocked_on(c.status, c.blocked_on),
          note: String.trim(c.note)
        }
    end
  end

  def execute(%__MODULE__{items: items, order: order}, %Commands.OrderWork{} = c) do
    given = List.wrap(c.order)

    cond do
      c.actor.kind not in @parties ->
        {:error, Error.new(:sunna_work_not_a_party, :sunna_work_order_not_a_party)}

      given == [] or Enum.uniq(given) != given or not Enum.all?(given, &Map.has_key?(items, &1)) ->
        {:error, Error.new(:sunna_work_invalid, :sunna_work_order_invalid)}

      true ->
        # The numbers given first, in the order given; the rest after, in
        # the order they had.
        %Events.WorkOrdered{actor: c.actor, at: c.at, id: c.id, order: given ++ (order -- given)}
    end
  end

  def execute(%__MODULE__{running: running}, %Commands.WrapWork{} = c) do
    cond do
      c.actor.kind != :resident ->
        {:error, Error.new(:sunna_work_not_a_party, :sunna_work_wrap_not_resident)}

      is_nil(running) or c.number != running ->
        {:error, Error.new(:sunna_work_not_running, :sunna_work_wrap_not_running)}

      not wrap_ok?(c) ->
        {:error, Error.new(:sunna_work_invalid, :sunna_work_wrap_invalid)}

      true ->
        %Events.WorkWrapped{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          shipped: String.trim(c.shipped),
          slipped: c.slipped && String.trim(c.slipped),
          why: String.trim(c.why),
          status: c.status,
          blocked_on: blocked_on(c.status, c.blocked_on)
        }
    end
  end

  # A claim: nothing when the loop is already running an item or the item
  # is not open, so a second check in the same minute starts nothing.
  def execute(%__MODULE__{running: nil, items: items}, %Commands.StartWork{} = c) do
    case Map.get(items, c.number) do
      %{status: "open"} ->
        %Events.WorkStarted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          session_key: c.session_key,
          day: c.day
        }

      _other ->
        []
    end
  end

  def execute(%__MODULE__{}, %Commands.StartWork{}), do: []

  def execute(%__MODULE__{running: n} = s, %Commands.EndWork{number: n} = c)
      when not is_nil(n) do
    status = with "in_work" <- s.items[n].status, do: "open"

    %Events.WorkRunEnded{
      actor: c.actor,
      at: c.at,
      id: c.id,
      number: n,
      wrapped: s.wrapped,
      status: status,
      stopped: c.stopped == true
    }
  end

  def execute(%__MODULE__{}, %Commands.EndWork{}), do: []

  def execute(%__MODULE__{running: nil, rested: rested}, %Commands.RestWork{} = c) do
    if c.reason == rested or not words?(c.reason, 300),
      do: [],
      else: %Events.WorkRested{actor: c.actor, at: c.at, id: c.id, reason: c.reason}
  end

  def execute(%__MODULE__{}, %Commands.RestWork{}), do: []

  def apply(%__MODULE__{} = s, %Events.WorkAdded{number: n}),
    do: %{
      s
      | next: n + 1,
        items: Map.put(s.items, n, %{status: "open"}),
        order: s.order ++ [n],
        rested: nil
    }

  def apply(%__MODULE__{} = s, %Events.WorkMoved{number: n, status: status}),
    do: %{s | items: Map.put(s.items, n, %{status: status}), rested: nil}

  def apply(%__MODULE__{} = s, %Events.WorkOrdered{order: order}),
    do: %{s | order: order, rested: nil}

  def apply(%__MODULE__{} = s, %Events.WorkWrapped{number: n, status: status}),
    do: %{s | items: Map.put(s.items, n, %{status: status}), wrapped: true}

  def apply(%__MODULE__{} = s, %Events.WorkStarted{number: n}),
    do: %{
      s
      | items: Map.put(s.items, n, %{status: "in_work"}),
        running: n,
        wrapped: false,
        rested: nil
    }

  def apply(%__MODULE__{} = s, %Events.WorkRunEnded{number: n, status: status} = e),
    do: %{
      s
      | items: Map.put(s.items, n, %{status: status}),
        running: nil,
        wrapped: false,
        rested: if(e.stopped, do: stopped_rest(), else: s.rested)
    }

  def apply(%__MODULE__{} = s, %Events.WorkRested{reason: reason}), do: %{s | rested: reason}

  @doc "The rest a stopped run leaves the loop in, until either party touches the queue."
  def stopped_rest,
    do: "stopped: the last run was stopped; the loop waits for the queue to be touched"

  defp wrap_ok?(c),
    do:
      status_ok?(c.status, c.blocked_on, @wrapped) and words?(c.shipped, @words) and
        words?(c.why, @words) and optional_words?(c.slipped)

  defp status_ok?("blocked", blocked_on, allowed),
    do: "blocked" in allowed and words?(blocked_on, 120)

  defp status_ok?(status, _blocked_on, allowed), do: status in allowed

  defp blocked_on("blocked", on), do: String.trim(on)
  defp blocked_on(_status, _on), do: nil

  defp words?(text, max),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= max

  defp optional_words?(nil), do: true
  defp optional_words?(text), do: is_binary(text) and String.length(text) <= @words
end
