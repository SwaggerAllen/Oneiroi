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
  `blocked` (on another queue item, by its number: sunna#42), `held`
  (waiting on the witness, with the ask: sunna#54), `done`, `dropped`.
  Blocked is work waiting on work, a dependency the loop can see: when
  the blocking item is done or dropped, what it blocked opens again.
  Held is work waiting on him: either party holds it with an ask in
  plain words, it lights his list (brain#86), the loop steps over it,
  and it clears only when the item is moved (released open with a note,
  done, dropped) or started (sunna#55).
  """

  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Events

  defstruct next: 1,
            items: %{},
            order: [],
            running: nil,
            wrapped: false,
            rested: nil,
            armed: false

  @parties [:resident, :witness]
  @moved ~w(open blocked held done dropped)
  @wrapped ~w(open blocked held done)
  @what 300
  # What a held item asks of the witness (sunna#54): a sentence or two,
  # the title of an entry on his list.
  @ask 500
  @words 4_000
  # What blocks an item, named (sunna#36, platform report #7): 300, after
  # 120 refused a reasonable name and said nothing of why.

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

  def execute(%__MODULE__{items: items} = s, %Commands.MoveWork{} = c) do
    cond do
      c.actor.kind not in @parties ->
        {:error, Error.new(:sunna_work_not_a_party, :sunna_work_move_not_a_party)}

      not Map.has_key?(items, c.number) ->
        {:error, Error.new(:sunna_no_such_work, :sunna_work_move_unknown)}

      refused = waiting_refused(items, c) ->
        {:error, refused}

      not status_ok?(c.status, @moved) or not words?(c.note, @words) ->
        {:error, Error.new(:sunna_work_invalid, :sunna_work_move_invalid)}

      true ->
        moved = moved(items, c)

        # Moving the running item by hand ends its run (sunna#37): the
        # loop's state never says it is running an item that is done,
        # dropped, blocked or held.
        ended =
          if s.running == c.number,
            do: [
              %Events.WorkRunEnded{
                actor: c.actor,
                at: c.at,
                id: c.id,
                number: c.number,
                wrapped: s.wrapped,
                status: c.status,
                stopped: false
              }
            ],
            else: []

        [moved | ended] ++ release(items, c.number, c.status, c)
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

  def execute(%__MODULE__{running: running} = s, %Commands.WrapWork{} = c) do
    cond do
      c.actor.kind != :resident ->
        {:error, Error.new(:sunna_work_not_a_party, :sunna_work_wrap_not_resident)}

      is_nil(running) or c.number != running ->
        {:error, Error.new(:sunna_work_not_running, :sunna_work_wrap_not_running)}

      refused = waiting_refused(s.items, c) ->
        {:error, refused}

      not wrap_ok?(c) ->
        {:error, Error.new(:sunna_work_invalid, :sunna_work_wrap_invalid)}

      true ->
        wrapped = %Events.WorkWrapped{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          shipped: String.trim(c.shipped),
          slipped: c.slipped && String.trim(c.slipped),
          why: String.trim(c.why),
          status: c.status,
          blocked_on: blocked_on(s.items, c.number, c.status, c.blocked_on)
        }

        # Held at the wrap (sunna#56): the residue is his word, so the
        # wrap records where the item stands and the hold carries the ask.
        held =
          if c.status == "held",
            do: [
              %Events.WorkHeld{
                actor: c.actor,
                at: c.at,
                id: c.id,
                number: c.number,
                ask: String.trim(c.ask),
                note: String.trim(c.why)
              }
            ],
            else: []

        [wrapped | held] ++ release(s.items, c.number, c.status, c)
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

  # The arm (sunna#35, the witness's call): hers alone, by tool call, once
  # a batch; nothing when already armed.
  def execute(%__MODULE__{armed: true}, %Commands.ArmWork{}), do: []

  # Either party arms (sunna#43, the witness, 2026-11-09: one mechanism,
  # two callers, her tool and his button); the event's actor is the
  # receipt of who did.
  def execute(%__MODULE__{}, %Commands.ArmWork{} = c) do
    if c.actor.kind in @parties,
      do: %Events.WorkArmed{actor: c.actor, at: c.at, id: c.id},
      else: {:error, Error.new(:sunna_work_not_a_party, :sunna_work_arm_not_a_party)}
  end

  # The witness turns the line off by hand at any moment (sunna#43): the
  # run in work finishes, and nothing starts after it until it is armed
  # again. The loop's own off is only when the queue is clear and nothing
  # runs (sunna#35).
  def execute(%__MODULE__{armed: true}, %Commands.DisarmWork{actor: %{kind: :witness}} = c),
    do: %Events.WorkDisarmed{actor: c.actor, at: c.at, id: c.id}

  def execute(%__MODULE__{}, %Commands.DisarmWork{actor: %{kind: kind}})
      when kind in [:witness, :resident],
      do: []

  def execute(%__MODULE__{armed: true, running: nil}, %Commands.DisarmWork{} = c),
    do: %Events.WorkDisarmed{actor: c.actor, at: c.at, id: c.id}

  def execute(%__MODULE__{}, %Commands.DisarmWork{}), do: []

  # The day's runs given back (sunna#53): the witness's, with a note.
  def execute(%__MODULE__{}, %Commands.ResetWorkRuns{actor: %{kind: :witness}} = c),
    do: %Events.WorkRunsReset{actor: c.actor, at: c.at, id: c.id, note: c.note}

  def execute(%__MODULE__{}, %Commands.ResetWorkRuns{}),
    do: {:error, Error.new(:sunna_work_not_a_party, :sunna_work_reset_witness_only)}

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

  def apply(%__MODULE__{} = s, %Events.WorkMoved{number: n, status: status} = e),
    do: %{s | items: Map.put(s.items, n, item(status, e.blocked_on)), rested: nil}

  def apply(%__MODULE__{} = s, %Events.WorkHeld{number: n}),
    do: %{s | items: Map.put(s.items, n, item("held", nil)), rested: nil}

  def apply(%__MODULE__{} = s, %Events.WorkOrdered{order: order}),
    do: %{s | order: order, rested: nil}

  def apply(%__MODULE__{} = s, %Events.WorkWrapped{number: n, status: status} = e),
    do: %{s | items: Map.put(s.items, n, item(status, e.blocked_on)), wrapped: true}

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
  def apply(%__MODULE__{} = s, %Events.WorkArmed{}), do: %{s | armed: true, rested: nil}
  def apply(%__MODULE__{} = s, %Events.WorkDisarmed{}), do: %{s | armed: false}
  # The count lives in the projection; the stream keeps the act and its note.
  def apply(%__MODULE__{} = s, %Events.WorkRunsReset{}), do: s

  @doc "The rest a stopped run leaves the loop in, until either party touches the queue."
  def stopped_rest,
    do: "stopped: the last run was stopped; the loop waits for the queue to be touched"

  # What a blocked or held status names as waited on (sunna#42, #54):
  # another item by its number, or an ask in words; nil when well formed.
  defp waiting_refused(items, %Commands.MoveWork{} = c) do
    cond do
      c.status == "blocked" and blocker(items, c.number, c.blocked_on) == :error ->
        Error.new(:sunna_work_blocked_on_invalid, :sunna_work_move_blocked_on)

      c.status == "held" and not words?(c.ask, @ask) ->
        Error.new(:sunna_work_ask_invalid, :sunna_work_move_ask)

      true ->
        nil
    end
  end

  defp waiting_refused(items, %Commands.WrapWork{} = c) do
    cond do
      c.status == "blocked" and blocker(items, c.number, c.blocked_on) == :error ->
        Error.new(:sunna_work_blocked_on_invalid, :sunna_work_wrap_blocked_on)

      c.status == "held" and not words?(c.ask, @ask) ->
        Error.new(:sunna_work_ask_invalid, :sunna_work_wrap_ask)

      true ->
        nil
    end
  end

  # A move to held is `WorkHeld`, carrying the ask (sunna#54); every other
  # status is `WorkMoved`.
  defp moved(_items, %{status: "held"} = c),
    do: %Events.WorkHeld{
      actor: c.actor,
      at: c.at,
      id: c.id,
      number: c.number,
      ask: String.trim(c.ask),
      note: String.trim(c.note)
    }

  defp moved(items, c),
    do: %Events.WorkMoved{
      actor: c.actor,
      at: c.at,
      id: c.id,
      number: c.number,
      status: c.status,
      blocked_on: blocked_on(items, c.number, c.status, c.blocked_on),
      note: String.trim(c.note)
    }

  defp wrap_ok?(c),
    do:
      status_ok?(c.status, @wrapped) and words?(c.shipped, @words) and
        words?(c.why, @words) and optional_words?(c.slipped)

  defp status_ok?(status, allowed), do: status in allowed

  defp item(status, blocked_on), do: %{status: status, blocked_on: blocked_on}

  # What blocks an item (sunna#42): another item of the queue, by its
  # number ("12", "#12", 12), that is still to be done and is not itself
  # waiting on this one; the stored form is "#12".
  defp blocker(items, self, raw) do
    with {:ok, n} <- number(raw),
         true <- n != self,
         %{status: status} = other when status not in ["done", "dropped"] <- items[n],
         true <- Map.get(other, :blocked_on) != "##{self}" do
      {:ok, n}
    else
      _ -> :error
    end
  end

  defp number(n) when is_integer(n) and n > 0, do: {:ok, n}

  defp number(raw) when is_binary(raw) do
    case Integer.parse(String.trim_leading(String.trim(raw), "#")) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp number(_other), do: :error

  defp blocked_on(items, self, "blocked", raw) do
    {:ok, n} = blocker(items, self, raw)
    "##{n}"
  end

  defp blocked_on(_items, _self, _status, _raw), do: nil

  # What an item blocked opens again when it is done or dropped
  # (sunna#42), each moved with a note saying why.
  defp release(items, n, status, c) when status in ["done", "dropped"] do
    for {m, %{status: "blocked", blocked_on: on}} <- Enum.sort(items), on == "##{n}" do
      %Events.WorkMoved{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: m,
        status: "open",
        blocked_on: nil,
        note: "Item ##{n} is #{status}, so this is no longer blocked."
      }
    end
  end

  defp release(_items, _n, _status, _c), do: []

  defp words?(text, max),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= max

  defp optional_words?(nil), do: true
  defp optional_words?(text), do: is_binary(text) and String.length(text) <= @words
end
