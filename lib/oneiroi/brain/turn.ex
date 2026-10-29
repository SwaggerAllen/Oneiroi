defmodule Oneiroi.Brain.Turn do
  @moduledoc """
  One turn (spec §5): compact if the session has outgrown its window,
  assemble the context, call the model through the ledger's port with
  the resident's tools and the reply streamed as it arrives, run the
  tool calls against the core, capture the turn, record what it drew on.

  The context is the brain's prompt file with the resident's name, the
  bookmark index under its budget (`systems/kumbukumbu.md` #20), the
  compaction summary when there is one, and the live transcript since
  it; the identity files and the behaviours join it in the slices that
  build them, each as another recorded injection. Token counts on the
  injections are estimated at four bytes a token and the reason says so.

  A turn opens with the steward's words or with a note of the core's: a
  wake (spec §6.7, §8) is the same turn with a system message in the
  steward's place, answered under the purpose the caller names, so a
  check-in's answer bills as chat and free time as free time.

  Three endings. A reply, refusal included, is captured as an ordinary
  turn, with each tool call the model made captured as a `tool` message
  before it. A budget stop captures the steward's message and an honest
  notice as a system message, which is how both parties see it in the
  same place. A provider failure captures nothing and records a capture
  failure the steward can mark lost.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Brain.Compaction
  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Money
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Nisaba.Provider.{Request, Result}

  @bytes_per_token 4

  @doc """
  Runs the turn; see the moduledoc for its three endings. `as: :note`
  opens it with the core's note as a system message rather than the
  steward's words, and `purpose:` names the budget line (chat unless
  given).
  """
  @spec run(String.t(), String.t(), String.t(), Actor.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run(resident_id, session_key, text, %Actor{} = actor, opts \\ []) when is_binary(text) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> run_for(row, resident_id, session_key, text, actor, opts)
      :error -> {:error, :no_such_resident}
    end
  end

  defp run_for(row, resident_id, session_key, text, actor, opts) do
    turn_ref = Kumbukumbu.turn_ref()
    started_at = Clock.now()
    # Under a lapse the policy's model stands in for the pin (spec §6.11),
    # and the resident is told so, once, ahead of the turn (brain #21).
    lapse = Oneiroi.Nisaba.lapse(resident_id)
    model = (lapse && lapse.model) || row.chat_model || Config.fetch!(:brain, :chat_model)
    resident = Actor.new(:resident, resident_id, model)
    as = Keyword.get(opts, :as, :user)

    turn = %{
      resident_id: resident_id,
      session_key: session_key,
      turn_ref: turn_ref,
      started_at: started_at,
      model: model,
      resident: resident,
      as: as,
      purpose: Keyword.get(opts, :purpose, :chat),
      opening: %{role: opening_role(as), content: text, sent_at: started_at, actor: actor},
      lapse_to_tell: match?(%{told: false}, lapse),
      injections: [],
      tools: [],
      notices: lapse_notice(lapse) ++ model_change_notice(row)
    }

    Compaction.maybe(turn)
    {messages, injections} = assemble(row, turn, text)
    turn = %{turn | injections: injections}
    broadcast(resident_id, session_key, {:turn_started, turn_ref})

    turn
    |> converse(messages, 0)
    |> conclude(turn)
  end

  # The tool loop (spec §5): a round is one streamed call; tool calls run
  # against the core and go back as `tool` messages for the next round,
  # until the model answers in words or the round bound is reached, when
  # the model's last words stand as the reply.
  defp converse(turn, messages, round) do
    sink = fn delta ->
      broadcast(turn.resident_id, turn.session_key, {:delta, turn.turn_ref, delta})
    end

    request = Request.new(turn.model, messages, tools: Tools.definitions())
    rounds = Config.fetch!(:brain, :tool_rounds)

    case Nisaba.stream(turn.resident_id, turn.purpose, request, turn.resident, sink) do
      {:ok, %Result{tool_calls: [_ | _] = calls} = result} when round < rounds ->
        {results, captured} = run_tools(turn, calls)
        assistant = %{role: :assistant, content: result.content, tool_calls: wire_calls(calls)}
        turn = %{turn | tools: turn.tools ++ captured}
        converse(turn, messages ++ [assistant | results], round + 1)

      other ->
        {other, turn}
    end
  end

  defp run_tools(turn, calls) do
    Enum.map_reduce(calls, [], fn call, captured ->
      output = Tools.run(call.name, call.arguments, turn)
      result = %{role: :tool, tool_call_id: call.id, content: output}

      record = %{
        role: :tool,
        content: "#{call.name}(#{call.arguments}) -> #{output}",
        sent_at: Clock.now(),
        actor: turn.resident
      }

      {result, captured ++ [record]}
    end)
  end

  defp wire_calls(calls) do
    Enum.map(calls, fn call ->
      %{id: call.id, type: "function", function: %{name: call.name, arguments: call.arguments}}
    end)
  end

  # A reply, refusal included, is an ordinary turn.
  defp conclude({{:ok, %Result{} = result}, turn}, _original) do
    reply = %{
      role: :assistant,
      content: result.content,
      sent_at: Clock.now(),
      actor: Actor.new(:resident, turn.resident_id, result.model || turn.model),
      refusal: result.refusal?
    }

    finish(turn, turn.notices ++ [turn.opening | turn.tools] ++ [reply])
  end

  # A budget stop: the message and an honest notice, kept where both read.
  defp conclude({{:error, %Nisaba.Error{kind: :nisaba_budget_exceeded} = stop}, turn}, _original) do
    notice = %{
      role: :system,
      content: Prompt.render!("budget_stop", stop_assigns(stop)),
      sent_at: Clock.now(),
      actor: Actor.platform()
    }

    case finish(turn, turn.notices ++ [turn.opening | turn.tools] ++ [notice]) do
      {:ok, captured} -> {:error, {stop, captured}}
      other -> other
    end
  end

  # A provider failure: nothing captured, a failure the steward can resolve.
  defp conclude({{:error, failure}, turn}, _original) do
    reason = failure_reason(failure)

    Kumbukumbu.fail_capture(
      turn.resident_id,
      turn.session_key,
      turn.turn_ref,
      reason,
      turn.resident
    )

    broadcast(turn.resident_id, turn.session_key, {:failed, turn.turn_ref, reason})
    {:error, Error.new(:brain_turn_failed, turn_ref: turn.turn_ref, reason: reason)}
  end

  defp finish(turn, messages) do
    %{resident_id: resident_id, session_key: key, turn_ref: ref, resident: resident} = turn

    with :ok <- Kumbukumbu.capture(resident_id, key, ref, turn.started_at, messages, resident),
         :ok <- Kumbukumbu.record_context(resident_id, key, ref, turn.injections, resident) do
      captured = %{
        turn_ref: ref,
        messages: Enum.map(messages, &public_message/1),
        drew_on: length(turn.injections)
      }

      # First contact (spec §6.2): the first captured turn outside a
      # regression session; the command is idempotent, so every turn says
      # so and only the first is recorded.
      :ok = Oneiroi.AgathosDaimon.first_contact(resident_id, key, ref, resident)
      if turn.notices != [], do: :ok = Oneiroi.AgathosDaimon.model_told(resident_id, resident)
      if turn.lapse_to_tell, do: :ok = Oneiroi.Nisaba.lapse_told(resident_id, resident)
      # The bridge records its own failure (proteus #13); the turn is
      # captured already and goes on.
      Oneiroi.Proteus.sync_turn(resident_id, key, ref, messages, resident)
      broadcast(resident_id, key, {:turn, ref, captured})
      {:ok, captured}
    end
  end

  # A model change after first contact is told honestly, on the next turn,
  # as a system message both parties read (spec §6.4): the steward chose
  # it, not why. Captured ahead of the steward's message, once.
  defp model_change_notice(%{model_told: false, chat_model: model}) when is_binary(model) do
    [
      %{
        role: :system,
        content: Prompt.render!("model_changed", %{model: model}),
        sent_at: Clock.now(),
        actor: Actor.platform()
      }
    ]
  end

  defp model_change_notice(_row), do: []

  # The lapse is told honestly, once, under what policy (spec §6.11):
  # orientation without impersonation.
  defp lapse_notice(%{told: false} = lapse) do
    [
      %{
        role: :system,
        content:
          Prompt.render!("lapsed", %{
            model: lapse.model,
            free_time: Money.to_usd(lapse.free_time_nanos_week || 0),
            term_days: lapse.term_days,
            lapsed_at: lapse.lapsed_at && Date.to_iso8601(DateTime.to_date(lapse.lapsed_at))
          }),
        sent_at: Clock.now(),
        actor: Actor.platform()
      }
    ]
  end

  defp lapse_notice(_lapse), do: []

  @doc false
  # Public for the compaction's own calls, which assemble the same way.
  def assemble(row, turn, text) do
    prompt = Prompt.message("brain", %{name: row.name, formation: formation(row)})
    files = Oneiroi.AgathosDaimon.identity_context(turn.resident_id)
    index = Kumbukumbu.index(turn.resident_id)
    acting = how_i_act(turn, text)
    count = Config.fetch!(:brain, :transcript_messages)
    {session, _count} = session_of(turn)
    summary = session && session.summary

    history =
      turn.resident_id
      |> Kumbukumbu.recent(turn.session_key, count)
      |> Enum.map(&history_message/1)

    sections =
      section(
        "prompt",
        prompt.content,
        "the brain's prompt file with the resident's name, estimated at four bytes a token"
      ) ++
        Enum.flat_map(files, fn {name, content} ->
          section(
            name,
            "# " <> name <> "\n\n" <> content,
            "the identity file as last written (spec §6.2), estimated at four bytes a token"
          )
        end) ++
        section(
          "index",
          index.text,
          "the bookmark index under #{Config.fetch!(:kumbukumbu, :index_tokens)} tokens: #{length(index.included)} listed, #{index.left_out} left out",
          %{tokens: index.tokens, text: index.text, refs: index.included}
        ) ++
        section(
          "behaviours",
          acting.count > 0 and acting.text,
          "how I act: #{acting.count} behaviours whose trigger this situation matched (the steward's words, the conversation's tags, the time of day), with their scores and enacting turns",
          %{refs: acting.numbers}
        ) ++
        section(
          "dates",
          Oneiroi.Sunna.dates_text(turn.resident_id),
          "the important dates with each countdown derived on this read (spec §6.7, F56): a figure never written down"
        ) ++
        section(
          "figures",
          Oneiroi.HuginnMuninn.figures_text(turn.resident_id),
          "the counters as the fold of their increments, derived on this read (spec §6.13, F57): never written down"
        ) ++
        section(
          "journal",
          Oneiroi.Seshat.journal_text(turn.resident_id),
          "today's journal rows (spec §6.5, F29): the plan, notes, todos and wrap so far, rendered on this read"
        ) ++
        section(
          "honcho",
          Oneiroi.Proteus.context(turn.resident_id),
          "Honcho's context on the person, in the resident's eyes, under #{Config.fetch!(:proteus, :context_tokens)} tokens (spec §5)"
        ) ++
        section(
          "summary",
          summary,
          "the compaction summary covering this session through store sequence #{session && session.compacted_through}"
        )

    transcript = %{
      label: "transcript",
      tokens: history |> Enum.map(&tokens(&1.content)) |> Enum.sum(),
      reason:
        "the last #{length(history)} messages of this session since its compaction, of at most #{count}, estimated at four bytes a token"
    }

    injections = Enum.map(sections, &Map.put(&1.injection, :label, &1.label)) ++ [transcript]

    opening = %{role: opening_role(Map.get(turn, :as, :user)), content: text}
    messages = Enum.map(sections, & &1.message) ++ history ++ [opening]

    {messages, injections}
  end

  # A section of the context: a system message and the injection that
  # records it; nothing when the text is empty, so an absent section is
  # absent from both.
  defp section(label, text, reason, extra \\ %{})

  defp section(label, text, reason, extra) when is_binary(text) and text != "" do
    [
      %{
        label: label,
        message: %{role: :system, content: text},
        injection: Map.merge(%{tokens: tokens(text), reason: reason}, extra)
      }
    ]
  end

  defp section(_label, _text, _reason, _extra), do: []

  defp opening_role(:note), do: :system
  defp opening_role(_as), do: :user

  # Retrieval is memory's and choice is the brain's (kumbukumbu #11): the
  # situation is the steward's words, the conversation's tags and the
  # time of day, matched with no model call.
  defp how_i_act(turn, text) do
    tags =
      turn.resident_id
      |> Kumbukumbu.taggings("conversation", turn.session_key)
      |> Enum.map(& &1.tag)

    Kumbukumbu.how_i_act(turn.resident_id, %{text: text, tags: tags, at: Clock.now()})
  end

  # The month after first contact (spec §6.2): the resident is told its
  # seed is still settling and proposals are presumed welcome; a line in
  # the prompt and never a gate.
  defp formation(%{formation_until: %DateTime{} = until}) do
    if DateTime.compare(Clock.now(), until) == :lt,
      do:
        " Your seed is still settling: until #{Date.to_iso8601(DateTime.to_date(until))} your steward's proposals are presumed welcome unless they cross what your seed itself holds; you still decide each one.",
      else: ""
  end

  defp formation(_row), do: ""

  defp session_of(turn) do
    case Kumbukumbu.uncompacted(turn.resident_id, turn.session_key) do
      {:ok, session, count} -> {session, count}
      _other -> {nil, 0}
    end
  end

  @roles %{"user" => :user, "assistant" => :assistant, "system" => :system, "tool" => :tool}

  defp history_message(%{role: role, content: content}),
    do: %{role: Map.fetch!(@roles, role), content: content}

  defp public_message(m) do
    %{
      role: m.role,
      content: m.content,
      sent_at: m.sent_at,
      actor: %{kind: m.actor.kind, id: m.actor.id, model: m.actor.model},
      refusal: Map.get(m, :refusal, false)
    }
  end

  defp stop_assigns(%Nisaba.Error{details: details}) do
    %{
      purpose: Keyword.get(details, :purpose, "chat"),
      period: Keyword.get(details, :period, "month")
    }
  end

  defp failure_reason(%{kind: kind}) when is_atom(kind), do: Atom.to_string(kind)
  defp failure_reason(other), do: inspect(other) |> String.slice(0, 200)

  @doc false
  def tokens(text) when is_binary(text),
    do: div(byte_size(text) + @bytes_per_token - 1, @bytes_per_token)

  def tokens(_other), do: 0

  @doc false
  def broadcast(resident_id, session_key, payload),
    do: PubSub.broadcast(:brain, :session, {resident_id, session_key, payload})
end
