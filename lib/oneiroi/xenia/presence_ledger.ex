defmodule Oneiroi.Xenia.PresenceLedger do
  @moduledoc """
  Presence (xenia#20) on `presence-<resident_id>`: the witness's switch
  and handle, the follow list and its mask, the day's passes, what the
  resident read in each, and the interactions staged from those reads on
  their way through the witness's review to being sent.

  The rules the design sets are held here, where a replay holds them too:

  - every interaction is earned by a read: only an item the resident read
    in the pass that drew it may be staged;
  - a pass stages at most its cap, and the cap may go unmet;
  - at most one interaction per account per day: a revision takes its
    predecessor's place, so a revised comment never counts twice;
  - an interaction is decided once while staged; a revision asked for
    leaves it waiting on the resident's new version, which supersedes it;
  - only an approved interaction is sent, once; the reader (hands) or
    the witness says it went out or failed.
  """

  alias Oneiroi.Xenia.Commands
  alias Oneiroi.Xenia.Error
  alias Oneiroi.Xenia.Events

  @kinds ~w(like comment restack)
  @decisions ~w(approve revise pass)

  defstruct excluded: MapSet.new(),
            known: MapSet.new(),
            passes: %{},
            interactions: %{},
            next_pass: 1,
            next_interaction: 1

  # ---- the witness's ----

  def execute(%__MODULE__{}, %Commands.SetPresence{actor: %{kind: k}}) when k != :witness,
    do: {:error, Error.new(:xenia_not_allowed, :xenia_presence_set_party)}

  def execute(%__MODULE__{}, %Commands.SetPresence{} = c),
    do: %Events.PresenceSet{
      actor: c.actor,
      at: c.at,
      id: c.id,
      enabled: c.enabled == true,
      handle: c.handle
    }

  def execute(%__MODULE__{}, %Commands.RecordFollows{} = c),
    do: %Events.FollowsRecorded{
      actor: c.actor,
      at: c.at,
      id: c.id,
      accounts: c.accounts,
      visible: c.visible
    }

  def execute(%__MODULE__{}, %{actor: %{kind: k}} = c)
      when k != :witness and is_struct(c, Commands.ExcludeAccount)
      when k != :witness and is_struct(c, Commands.IncludeAccount),
      do: {:error, Error.new(:xenia_not_allowed, :xenia_presence_mask_party)}

  def execute(%__MODULE__{} = s, %Commands.ExcludeAccount{} = c) do
    cond do
      not MapSet.member?(s.known, c.key) ->
        {:error, Error.new(:xenia_no_such_account, :xenia_presence_exclude_unknown)}

      MapSet.member?(s.excluded, c.key) ->
        []

      true ->
        %Events.AccountExcluded{actor: c.actor, at: c.at, id: c.id, key: c.key, note: c.note}
    end
  end

  def execute(%__MODULE__{} = s, %Commands.IncludeAccount{} = c) do
    if MapSet.member?(s.excluded, c.key),
      do: %Events.AccountIncluded{actor: c.actor, at: c.at, id: c.id, key: c.key, note: c.note},
      else: []
  end

  # ---- the day's pass ----

  def execute(%__MODULE__{} = s, %Commands.DrawPass{} = c) do
    if Enum.any?(s.passes, fn {_n, p} -> p.day == c.day end),
      do: {:error, Error.new(:xenia_presence_drawn, :xenia_presence_draw_twice)},
      else: %Events.PassDrawn{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: s.next_pass,
        day: c.day,
        accounts: c.accounts,
        pool: c.pool,
        ranked: c.ranked,
        serendipity: c.serendipity,
        cap: c.cap,
        reads: c.reads
      }
  end

  # ---- the resident's ----

  def execute(%__MODULE__{}, %{actor: %{kind: k}} = c)
      when k != :resident and is_struct(c, Commands.ReadItem)
      when k != :resident and is_struct(c, Commands.StageInteraction),
      do: {:error, Error.new(:xenia_not_allowed, :xenia_presence_resident_party)}

  def execute(%__MODULE__{} = s, %Commands.ReadItem{} = c) do
    case Map.fetch(s.passes, c.pass) do
      {:ok, pass} ->
        cond do
          not Map.has_key?(pass.items, c.item) ->
            {:error, Error.new(:xenia_presence_not_drawn, :xenia_presence_read_undrawn)}

          MapSet.member?(pass.read, c.item) ->
            []

          true ->
            %Events.ItemRead{actor: c.actor, at: c.at, id: c.id, pass: c.pass, item: c.item}
        end

      :error ->
        {:error, Error.new(:xenia_presence_not_drawn, :xenia_presence_read_no_pass)}
    end
  end

  # A revision keeps the pass, item and account of what it revises: the
  # read already earned it, and it counts against that pass's cap.
  def execute(%__MODULE__{} = s, %Commands.StageInteraction{supersedes: n} = c)
      when is_integer(n) do
    with :ok <- kind_ok(c),
         {:ok, replacing} <- supersedable(s, n) do
      %Events.InteractionStaged{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: s.next_interaction,
        pass: replacing.pass,
        item: replacing.item,
        account: replacing.account,
        kind: c.kind,
        text: c.text,
        supersedes: n
      }
    end
  end

  def execute(%__MODULE__{} = s, %Commands.StageInteraction{} = c) do
    with {:ok, number, pass} <- current_pass(s),
         :ok <- kind_ok(c),
         {:ok, account} <- read_in(pass, c.item),
         :ok <- one_per_account(s, pass, account, nil),
         :ok <- under_cap(s, number, pass, nil) do
      %Events.InteractionStaged{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: s.next_interaction,
        pass: number,
        item: c.item,
        account: account,
        kind: c.kind,
        text: c.text,
        supersedes: nil
      }
    end
  end

  # ---- the review ----

  def execute(%__MODULE__{}, %Commands.DecideInteraction{actor: %{kind: k}}) when k != :witness,
    do: {:error, Error.new(:xenia_not_allowed, :xenia_presence_decide_party)}

  def execute(%__MODULE__{} = s, %Commands.DecideInteraction{} = c) do
    cond do
      c.decision not in @decisions ->
        {:error, Error.new(:xenia_presence_invalid, :xenia_presence_decision_invalid)}

      c.decision == "revise" and blank?(c.comment) ->
        {:error, Error.new(:xenia_presence_invalid, :xenia_presence_revise_comment)}

      true ->
        case Map.get(s.interactions, c.number) do
          %{state: :staged} ->
            %Events.InteractionDecided{
              actor: c.actor,
              at: c.at,
              id: c.id,
              number: c.number,
              decision: c.decision,
              comment: blank_nil(c.comment),
              release_at: if(c.decision == "approve", do: c.release_at)
            }

          nil ->
            {:error, Error.new(:xenia_no_such_interaction, :xenia_presence_decide_none)}

          _decided ->
            {:error, Error.new(:xenia_already_decided, :xenia_presence_decided_twice)}
        end
    end
  end

  # ---- the send ----

  def execute(%__MODULE__{}, %{actor: %{kind: k}} = c)
      when k not in [:hands, :witness] and is_struct(c, Commands.MarkInteractionSent)
      when k not in [:hands, :witness] and is_struct(c, Commands.FailInteraction),
      do: {:error, Error.new(:xenia_not_allowed, :xenia_presence_send_party)}

  def execute(%__MODULE__{} = s, %Commands.MarkInteractionSent{} = c) do
    case Map.get(s.interactions, c.number) do
      %{state: :approved} ->
        %Events.InteractionSent{actor: c.actor, at: c.at, id: c.id, number: c.number, url: c.url}

      %{state: :sent} ->
        []

      nil ->
        {:error, Error.new(:xenia_no_such_interaction, :xenia_presence_sent_none)}

      _other ->
        {:error, Error.new(:xenia_presence_not_approved, :xenia_presence_sent_unapproved)}
    end
  end

  def execute(%__MODULE__{} = s, %Commands.FailInteraction{} = c) do
    case Map.get(s.interactions, c.number) do
      %{state: :approved} ->
        %Events.InteractionFailed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          reason: c.reason
        }

      nil ->
        {:error, Error.new(:xenia_no_such_interaction, :xenia_presence_failed_none)}

      _other ->
        {:error, Error.new(:xenia_presence_not_approved, :xenia_presence_failed_unapproved)}
    end
  end

  # ---- checks ----

  # Staging belongs to the latest pass: yesterday's reads are spent.
  defp current_pass(%{next_pass: 1}),
    do: {:error, Error.new(:xenia_presence_not_drawn, :xenia_presence_stage_no_pass)}

  defp current_pass(s) do
    number = s.next_pass - 1
    {:ok, number, Map.fetch!(s.passes, number)}
  end

  defp kind_ok(%{kind: "comment", text: text}) do
    if blank?(text),
      do: {:error, Error.new(:xenia_presence_invalid, :xenia_presence_comment_blank)},
      else: :ok
  end

  defp kind_ok(%{kind: kind}) when kind in @kinds, do: :ok

  defp kind_ok(_c),
    do: {:error, Error.new(:xenia_presence_invalid, :xenia_presence_kind_invalid)}

  defp read_in(pass, item) do
    cond do
      not Map.has_key?(pass.items, item) ->
        {:error, Error.new(:xenia_presence_not_drawn, :xenia_presence_stage_undrawn)}

      not MapSet.member?(pass.read, item) ->
        {:error, Error.new(:xenia_presence_unread, :xenia_presence_stage_unread)}

      true ->
        {:ok, Map.fetch!(pass.items, item)}
    end
  end

  defp supersedable(s, number) do
    case Map.get(s.interactions, number) do
      %{state: state} = i when state in [:staged, :revise] -> {:ok, i}
      nil -> {:error, Error.new(:xenia_no_such_interaction, :xenia_presence_supersede_none)}
      _other -> {:error, Error.new(:xenia_not_supersedable, :xenia_presence_supersede_decided)}
    end
  end

  # Live interactions are those not passed over, not superseded and not
  # failed; the one being replaced does not count against its successor.
  defp live(s, replacing) do
    skip = if replacing, do: replacing.number

    for {n, i} <- s.interactions, n != skip, i.state not in [:passed, :superseded, :failed], do: i
  end

  defp one_per_account(s, pass, account, replacing) do
    if Enum.any?(live(s, replacing), &(&1.account == account and &1.day == pass.day)),
      do: {:error, Error.new(:xenia_presence_account_today, :xenia_presence_one_per_account)},
      else: :ok
  end

  defp under_cap(s, number, pass, replacing) do
    if Enum.count(live(s, replacing), &(&1.pass == number)) >= pass.cap,
      do: {:error, Error.new(:xenia_presence_cap, :xenia_presence_over_cap)},
      else: :ok
  end

  defp blank?(text), do: not is_binary(text) or String.trim(text) == ""
  defp blank_nil(text), do: if(blank?(text), do: nil, else: text)

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.PresenceSet{}), do: s

  def apply(%__MODULE__{} = s, %Events.FollowsRecorded{} = e),
    do: %{s | known: MapSet.union(s.known, MapSet.new(e.accounts, &field(&1, :key)))}

  def apply(%__MODULE__{} = s, %Events.AccountExcluded{} = e),
    do: %{s | excluded: MapSet.put(s.excluded, e.key)}

  def apply(%__MODULE__{} = s, %Events.AccountIncluded{} = e),
    do: %{s | excluded: MapSet.delete(s.excluded, e.key)}

  def apply(%__MODULE__{} = s, %Events.PassDrawn{} = e) do
    items = Map.new(e.reads, &{field(&1, :key), field(&1, :account)})
    pass = %{day: e.day, cap: e.cap, items: items, read: MapSet.new()}
    %{s | passes: Map.put(s.passes, e.number, pass), next_pass: e.number + 1}
  end

  def apply(%__MODULE__{} = s, %Events.ItemRead{} = e),
    do: update_in(s.passes[e.pass].read, &MapSet.put(&1, e.item))

  def apply(%__MODULE__{} = s, %Events.InteractionStaged{} = e) do
    interaction = %{
      number: e.number,
      pass: e.pass,
      day: s.passes[e.pass].day,
      item: e.item,
      account: e.account,
      state: :staged
    }

    s = %{s | interactions: Map.put(s.interactions, e.number, interaction)}
    s = if e.supersedes, do: put_in(s.interactions[e.supersedes].state, :superseded), else: s
    %{s | next_interaction: e.number + 1}
  end

  def apply(%__MODULE__{} = s, %Events.InteractionDecided{} = e) do
    state =
      case e.decision do
        "approve" -> :approved
        "revise" -> :revise
        "pass" -> :passed
      end

    put_in(s.interactions[e.number].state, state)
  end

  def apply(%__MODULE__{} = s, %Events.InteractionSent{} = e),
    do: put_in(s.interactions[e.number].state, :sent)

  def apply(%__MODULE__{} = s, %Events.InteractionFailed{} = e),
    do: put_in(s.interactions[e.number].state, :failed)

  # An event's maps decode string-keyed; a fresh command's are atom-keyed.
  defp field(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
