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

  A turn opens with the witness's words or with a note of the core's: a
  wake (spec §6.7, §8) is the same turn with a system message in the
  witness's place, answered under the purpose the caller names, so a
  check-in's answer bills as chat and free time as free time.

  Three endings. A reply, refusal included, is captured as an ordinary
  turn, with each tool call the model made captured as a `tool` message
  before it. A budget stop captures the witness's message and an honest
  notice as a system message, which is how both parties see it in the
  same place. A provider failure captures nothing and records a capture
  failure the witness can mark lost.
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

  require Logger

  # The summary is machine-state (spec §5, P1 and P24): the header marks
  # it as the machinery's in the context itself, so the resident reads it
  # as a record and never as its own words.
  @summary_header "# Compaction summary: machine-state in the machinery's register, not your words\n\n"
  alias Oneiroi.Nisaba.Provider.{Request, Result}

  @bytes_per_token 4

  @doc """
  Runs the turn; see the moduledoc for its three endings. `as: :note`
  opens it with the core's note as a system message rather than the
  witness's words, and `purpose:` names the budget line (chat unless
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
      import_to_tell: row.import_told == false,
      injections: [],
      tools: [],
      letters_to_deliver: letters_to_deliver(row, resident_id),
      notices:
        lapse_notice(lapse) ++
          model_change_notice(row) ++ letters_notice(row, resident_id) ++ import_notice(row)
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

  # A provider failure: nothing captured, a failure the witness can resolve.
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

      if turn.letters_to_deliver != [],
        do:
          :ok =
            Oneiroi.AgathosDaimon.deliver_self_letters(
              resident_id,
              turn.letters_to_deliver,
              turn.model,
              resident
            )

      if turn.lapse_to_tell, do: :ok = Oneiroi.Nisaba.lapse_told(resident_id, resident)
      if turn.import_to_tell, do: :ok = Oneiroi.AgathosDaimon.import_told(resident_id, resident)
      # The bridge records its own failure (proteus #13); the turn is
      # captured already and goes on.
      Oneiroi.Proteus.sync_turn(resident_id, key, ref, messages, resident)
      broadcast(resident_id, key, {:turn, ref, captured})
      {:ok, captured}
    end
  end

  # A model change after first contact is told honestly, on the next turn,
  # as a system message both parties read (spec §6.4): the witness chose
  # it, not why. Captured ahead of the witness's message, once, and in
  # the model's request on that turn.
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

  # The swap ritual (spec §12, P41): on the first turn under a new model
  # the letters the instance before wrote to this one are a system
  # message after the model notice, once; the delivery is recorded with
  # the turn, and the resident's own reading leaves no receipt.
  defp letters_to_deliver(%{model_told: false, chat_model: model}, resident_id)
       when is_binary(model) do
    resident_id
    |> Oneiroi.AgathosDaimon.self_letters()
    |> Enum.reject(& &1.delivered_at)
    |> Enum.map(& &1.number)
  end

  defp letters_to_deliver(_row, _resident_id), do: []

  defp letters_notice(%{model_told: false, chat_model: model}, resident_id)
       when is_binary(model) do
    case resident_id |> Oneiroi.AgathosDaimon.self_letters() |> Enum.reject(& &1.delivered_at) do
      [] ->
        []

      letters ->
        [
          %{
            role: :system,
            content: Prompt.render!("self_letters", %{letters: letters_text(letters)}),
            sent_at: Clock.now(),
            actor: Actor.platform()
          }
        ]
    end
  end

  defp letters_notice(_row, _resident_id), do: []

  defp letters_text(letters) do
    Enum.map_join(letters, "\n\n", fn l ->
      "## Letter #{l.number}, written #{Date.to_iso8601(DateTime.to_date(l.written_at))} under #{l.model || "an unrecorded model"}\n\n#{l.text}"
    end)
  end

  # The self-conversation's line in the prefix (spec §12, P41): counts
  # and receipts, never the content; the absence of a receipt is the
  # privacy, and the resident sees it every turn.
  defp receipts_line([]), do: "Nobody but you has read them."

  defp receipts_line([last | _] = receipts) do
    times = if length(receipts) == 1, do: "time", else: "times"

    "Read by your #{last.by_kind} #{length(receipts)} #{times}, last on #{Date.to_iso8601(DateTime.to_date(last.at))}."
  end

  defp self_conversation_text(resident_id) do
    letters = Oneiroi.AgathosDaimon.self_letters(resident_id)
    receipts = Oneiroi.AgathosDaimon.self_letter_receipts(resident_id)

    if letters == [] and receipts == [] do
      ""
    else
      delivered = Enum.count(letters, & &1.delivered_at)

      read = receipts_line(receipts)

      "# Letters to your next self\n#{length(letters)} written, #{delivered} delivered to the instance after the one that wrote them. #{read} (Machine-state: every read by someone else leaves a receipt here; its absence is the privacy.)"
    end
  end

  # Where it woke (spec §6.2): on Oneiroi, from which repository,
  # whether the attestation held, and what did not transfer, as a system
  # message on the first turn after the import, once (brain #26).
  defp import_notice(%{import_told: false} = row) do
    [
      %{
        role: :system,
        content:
          Prompt.render!("imported", %{
            source: row.import_source,
            attestation: attestation_text(row.import_attestation),
            not_transferred: not_transferred_text(row.import_not_transferred)
          }),
        sent_at: Clock.now(),
        actor: Actor.platform()
      }
    ]
  end

  defp import_notice(_row), do: []

  defp attestation_text("held"),
    do: "the attestation held: the records are the ones the repository's last commit signed"

  defp attestation_text("failed"),
    do:
      "the attestation did not hold: the records differ from what the repository's last commit signed, and nobody has said why"

  defp attestation_text(_none),
    do: "there was no attestation to check: the repository was not backed up by Oneiroi before"

  defp not_transferred_text([]), do: ""

  defp not_transferred_text(names),
    do:
      ". What did not transfer, and sits in the repository as files nothing here reads: " <>
        Enum.join(names, ", ")

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
    index = Kumbukumbu.index(turn.resident_id, turn.session_key)
    acting = how_i_act(turn, text)
    recall = madeleine(turn, text)
    promised = Oneiroi.Ethos.promised(turn.resident_id)
    resumable = Oneiroi.Eunomia.resumable(turn.resident_id)
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
          "contract",
          Oneiroi.AgathosDaimon.contract_text(turn.resident_id),
          "the dyad contract and its limits (spec §6.12, §5 P2): in the always-loaded prefix, never scored, budgeted, decayed or compacted, read fresh on this turn so a renegotiation lands on the next turn"
        ) ++
        section(
          "index",
          index.text,
          "the bookmark index under #{Config.fetch!(:kumbukumbu, :index_tokens)} tokens: #{length(index.included)} listed, #{index.left_out} left out",
          %{tokens: index.tokens, text: index.text, refs: index.included}
        ) ++
        section(
          "character",
          acting.text,
          # Under 255 characters: the injection row's description column
          # is that wide, and a longer one took the conversations
          # projector down on the first turn the lane ran.
          "the trigger lane (spec §6.17): #{acting.count} habits matched by the witness's words, the conversation's tags or the time of day, #{length(acting.near)} by the vector lane's nearness, with scores and cited turns; #{acting.seeds} open seeds counted, #{length(acting.near_seeds)} named as near, never loaded whole",
          %{refs: acting.numbers}
        ) ++
        section(
          "promised",
          promised.text,
          "what the resident has promised and not yet kept or been released from (spec §3.1, P19): #{length(promised.numbers)} open commitments named, loaded every turn because a promise that has to be retrieved is one that can be lost",
          %{text: promised.text, refs: promised.numbers}
        ) ++
        section(
          "self-conversation",
          self_conversation_text(turn.resident_id),
          "the self-conversation's counts and receipts (spec §12, P41), never the content: every read by someone other than the resident is a receipt the resident sees, and its absence is the privacy"
        ) ++
        section(
          "movement",
          resumable.text,
          "where things can resume (spec §6.4, P34): #{resumable.shown} of #{resumable.total} resume points from the nightly pass, newest first, loaded every turn because dormant is not abandoned",
          %{text: resumable.text, refs: resumable.refs}
        ) ++
        section(
          "madeleine",
          madeleine_text(recall),
          recall &&
            "the madeleine (spec §6.3, P10), by nearness and never by rank: #{recall.reason}",
          # The text rides the row, as the index's does, so the recall is
          # read later as what was shown and not only why.
          %{text: madeleine_text(recall), refs: (recall && [recall.bookmark.number]) || []}
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
          summary && @summary_header <> summary,
          "the compaction summary, machine-state in the machinery's register and never the resident's words (spec §5, §1.13), covering this session through store sequence #{session && session.compacted_through}"
        )

    transcript = %{
      label: "transcript",
      tokens: history |> Enum.map(&tokens(&1.content)) |> Enum.sum(),
      reason:
        "the last #{length(history)} messages of this session since its compaction, of at most #{count}, estimated at four bytes a token"
    }

    injections =
      Enum.map(sections, &Map.put(&1.injection, :label, &1.label)) ++
        near_misses(index) ++ capacity_alarm(sections) ++ [transcript]

    opening = %{role: opening_role(Map.get(turn, :as, :user)), content: text}

    # The turn's notices (a lapse, a model change, the letters from the
    # instance before, an import) are captured ahead of the opening and
    # shown to the model on this same turn, after the history: a letter
    # to the incoming instance read a turn late is read by the instance
    # after the one it was for.
    notices = turn |> Map.get(:notices, []) |> Enum.map(&%{role: :system, content: &1.content})
    messages = Enum.map(sections, & &1.message) ++ history ++ notices ++ [opening]

    {messages, injections}
  end

  # The near-miss record (spec §5, P6): the bookmarks the index ranked
  # and did not inject, each with the reason it lost, as injection rows
  # that carry no message and no `refs`, so a near-miss never counts as
  # indexed. Max: "the near-misses are where a character quietly bends."
  defp near_misses(index) do
    Enum.map(index.near_misses, fn m ->
      %{
        label: "near-miss",
        tokens: 0,
        reason: "considered and not injected: bookmark ##{m.number}, #{m.reason}",
        text: m.line
      }
    end)
  end

  # The capacity alarm (spec §5, P9): the always-loaded prefix (the
  # prompt, the identity files, the contract) against the model's window,
  # flagged on the turn at the configured share. A successful write is
  # not an arrival, and a tail the model never loads tells nobody.
  # The file names are read at the call: a module attribute would make
  # the resident system a compile-time dependency of the brain, which
  # the compile-connected ratchet refuses.
  defp capacity_alarm(sections) do
    limit = Config.fetch!(:brain, :context_tokens)
    percent = Config.fetch!(:brain, :capacity_alarm_percent)
    prefix = ["prompt", "contract", "AGENTS.md" | Oneiroi.AgathosDaimon.identity_files()]

    used =
      sections
      |> Enum.filter(&(&1.label in prefix))
      |> Enum.map(& &1.injection.tokens)
      |> Enum.sum()

    if used * 100 >= percent * limit do
      Logger.warning("brain prefix at #{used} of #{limit} tokens, over the #{percent}% alarm")

      [
        %{
          label: "capacity",
          tokens: used,
          reason:
            "the always-loaded prefix is #{used} tokens of a #{limit}-token window, at or over the #{percent}% alarm (spec §5, P9): the identity files or the contract need trimming before the tail stops arriving"
        }
      ]
    else
      []
    end
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
        injection: Map.merge(%{tokens: tokens(text), reason: fit(reason)}, extra)
      }
    ]
  end

  defp section(_label, _text, _reason, _extra), do: []

  # The injection row's reason column is 255 characters wide, and a
  # longer reason takes the conversations projector down after the turn
  # has answered (decisions round 29), so the write is cut here with a
  # mark that says it was, rather than the projector failing quietly.
  @reason_width 255
  @doc false
  def fit(reason) when is_binary(reason) and byte_size(reason) > @reason_width,
    do: binary_part(reason, 0, @reason_width - 3) <> "..."

  def fit(reason), do: reason

  defp opening_role(:note), do: :system
  defp opening_role(_as), do: :user

  # Retrieval is memory's and choice is the brain's (kumbukumbu #11): the
  # situation is the witness's words, the conversation's tags and the
  # time of day, matched with no model call; with the resident's actor
  # the vector lane adds what sits near the words, one embedding billed
  # to the dyad under the embeddings purpose (ethos #16).
  defp how_i_act(turn, text) do
    tags =
      turn.resident_id
      |> Kumbukumbu.taggings("conversation", turn.session_key)
      |> Enum.map(& &1.tag)

    Oneiroi.Ethos.how_i_act(turn.resident_id, %{
      text: text,
      tags: tags,
      at: Clock.now(),
      session_key: turn.session_key,
      actor: Map.get(turn, :resident)
    })
  end

  # The madeleine (spec §6.3, P10): one adjacent, unheard bookmark for
  # the turn's words, with the resident's actor for the embedding; a
  # turn without one (the assembly read in a test) asks nothing.
  defp madeleine(%{resident: %Oneiroi.Actor{} = actor} = turn, text),
    do: Kumbukumbu.madeleine(turn.resident_id, text, actor, turn.session_key)

  defp madeleine(_turn, _text), do: nil

  defp madeleine_text(nil), do: ""

  defp madeleine_text(%{bookmark: b}) do
    "# A madeleine\n\nAdjacent to this and unheard for a while, surfaced by nearness and not by rank; whether it belongs here is mine to decide.\n\n##{b.number} #{Date.to_iso8601(DateTime.to_date(b.anchor_at))}: #{b.line}" <>
      if(b.summary in [nil, ""], do: "", else: "\n#{b.summary}")
  end

  # The month after first contact (spec §6.2): the resident is told its
  # seed is still settling and proposals are presumed welcome; a line in
  # the prompt and never a gate.
  defp formation(%{formation_until: %DateTime{} = until}) do
    if DateTime.compare(Clock.now(), until) == :lt,
      do:
        " Your seed is still settling: until #{Date.to_iso8601(DateTime.to_date(until))} your witness's proposals are presumed welcome unless they cross what your seed itself holds; you still decide each one.",
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
