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

  A regression trial (`trial/4`, eunomia #10) is the same turn in a fresh
  session that nobody opened: the same assembly, memory retrieval
  included, and the same tool loop, with the reads real and every tool
  that would change anything answered as on success and recorded nowhere
  (`Oneiroi.Brain.Tools.trial/3`). It is never captured, records no
  context, broadcasts nothing, compacts nothing and carries no notice,
  and every call it makes, embeddings included, bills under `regression`.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Brain.Compaction
  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.History
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
      {:ok, row} ->
        run_for(row, resident_id, session_key, text, actor, opts)

      :error ->
        {:error,
         Error.new(:brain_no_such_resident, :brain_turn_resident_absent, resident_id: resident_id)}
    end
  end

  @doc """
  Answers one regression trial (spec §6.4, eunomia #10): `prompt` as
  `model`, in a fresh session, with what a real turn there would have
  (the prefix with the formation line, the contract, the index, the
  character lane, the madeleine and every other section) and the whole
  tool surface, through the same loop. Nothing names the run, and the
  resident is not told it is in a trial.

  Nothing is written: the reads bill their embeddings under `regression`
  and read the vectors as they stand, every write tool answers as it does
  on success without running, and the turn is not captured, records no
  context, compacts nothing and broadcasts nothing. The once-only notices
  (a lapse, a model change, the letters to a next self, an import) are
  left out: each is owed to the resident's real next turn, and a letter
  read here would reach the witness on a card with no receipt (P41). The
  model calls bill to `actor`, the run's.

  The reply comes back with the trace of the loop's tool calls in order
  (`Oneiroi.Eunomia.Trial.step/0`): each tool, its arguments, whether it
  read or was mocked, and the text the model was given back. It is the
  witness's, for the card (eunomia #31): it rides the return and nothing
  else, never the session topic, a capture or a log.
  """
  @spec trial(String.t(), String.t(), String.t(), Actor.t()) ::
          {:ok, Result.t(), [Oneiroi.Eunomia.Trial.step()]} | {:error, term()}
  def trial(resident_id, model, prompt, %Actor{} = actor)
      when is_binary(model) and is_binary(prompt) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, row} ->
        trial_for(row, resident_id, model, prompt, actor)

      :error ->
        {:error,
         Error.new(:brain_no_such_resident, :brain_trial_resident_absent,
           resident_id: resident_id
         )}
    end
  end

  defp trial_for(row, resident_id, model, prompt, payer) do
    turn = %{
      resident_id: resident_id,
      # A session key nobody opened, the shape a real one has: no
      # history, no summary, no tags, and the common room's memory, as a
      # fresh session in the main room has.
      session_key: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false),
      turn_ref: Kumbukumbu.turn_ref(),
      started_at: Clock.now(),
      model: model,
      resident: Actor.new(:resident, resident_id, model),
      payer: payer,
      trial?: true,
      minted: %{},
      as: :user,
      purpose: :regression,
      notices: [],
      injections: [],
      tools: [],
      trace: []
    }

    {messages, _injections} = assemble(row, turn, prompt)

    case converse(turn, messages, 0) do
      {{:ok, %Result{} = result}, turn} -> {:ok, result, turn.trace}
      {failure, _turn} -> failure
    end
  end

  defp run_for(row, resident_id, session_key, text, actor, opts) do
    turn = prepare(row, resident_id, session_key, text, actor, opts)
    Compaction.maybe(turn)
    {messages, injections} = assemble(row, turn, text)
    # The once-only notices are recorded with their words on the turn
    # that tells them, so the reply's inspector shows what it was told
    # (brain #41); every other section keeps the text it kept before.
    turn = %{turn | injections: injections ++ notice_injections(turn)}
    broadcast(resident_id, session_key, {:turn_started, turn.turn_ref})

    turn
    |> converse(messages, 0)
    |> conclude(turn)
  end

  # The turn as it would open now: the model (a lapse's over the pin and
  # the setting), the resident's actor, the opening and the once-only
  # notices owed to it. A real turn and the witness's preview (brain #41)
  # both start here, so the preview cannot open a turn the turn would not.
  defp prepare(row, resident_id, session_key, text, actor, opts) do
    started_at = Clock.now()
    # Under a lapse the policy's model stands in for the pin (spec §6.11),
    # and the resident is told so, once, ahead of the turn (brain #21).
    lapse = Oneiroi.Nisaba.lapse(resident_id)
    model = (lapse && lapse.model) || row.chat_model || Config.fetch!(:brain, :chat_model)
    as = Keyword.get(opts, :as, :user)

    # Each notice with the kind it is, so the preview can name it
    # without its text; the turn carries the messages alone.
    notices = [
      lapse: lapse_notice(lapse),
      model_change: model_change_notice(row),
      letters: letters_notice(row, resident_id),
      import: import_notice(row)
    ]

    %{
      resident_id: resident_id,
      session_key: session_key,
      turn_ref: Kumbukumbu.turn_ref(),
      started_at: started_at,
      model: model,
      resident: Actor.new(:resident, resident_id, model),
      as: as,
      purpose: Keyword.get(opts, :purpose, :chat),
      opening: %{role: opening_role(as), content: text, sent_at: started_at, actor: actor},
      lapse_to_tell: match?(%{told: false}, lapse),
      import_to_tell: row.import_told == false,
      injections: [],
      tools: [],
      letters_to_deliver: letters_to_deliver(row, resident_id),
      notices: Enum.flat_map(notices, &elem(&1, 1)),
      notice_kinds: for({kind, [_ | _]} <- notices, do: kind)
    }
  end

  @doc """
  The next turn of `session_key` as a dry run, for the witness's
  preview (brain #41): the same `prepare/6` and the same assembly the
  turn runs, in the same order, with nothing after it. Nothing is
  compacted, captured, recorded, marked, broadcast or synced, and no
  model is called: the madeleine, whose query is an embedding billed to
  the dyad, is an entry saying it was not run, and the character lane
  matches on the words given with its vector lane left out, as a lane
  with no actor runs. Each entry is an injection the turn would record,
  with the text the context would carry; what of it the witness may
  read is `Oneiroi.Brain.Preview`'s to decide, not this function's.
  """
  @spec dry_run(map(), String.t(), String.t(), String.t(), Actor.t()) :: %{
          entries: [map()],
          compacts_first: boolean()
        }
  def dry_run(row, resident_id, session_key, text, %Actor{} = actor) do
    turn =
      row
      |> prepare(resident_id, session_key, text, actor, [])
      |> Map.put(:preview?, true)

    %{sections: sections, injections: injections} = build(row, turn, text)
    contents = Map.new(sections, &{&1.label, &1.message && &1.message.content})

    entries =
      Enum.map(injections, fn i ->
        %{
          label: i.label,
          tokens: i.tokens,
          reason: i.reason,
          text: Map.get(i, :text) || Map.get(contents, i.label),
          run: Map.get(i, :run, true)
        }
      end)

    notices = Enum.map(notice_injections(turn), &Map.put(&1, :run, true))

    %{entries: entries ++ notices, compacts_first: Compaction.due?(turn)}
  end

  # One injection a notice, after the transcript as the notices follow
  # the history in the request: label, tokens, the kind as the reason,
  # and the words, for the inspector of the reply that told them.
  defp notice_injections(turn) do
    Enum.zip_with(turn.notice_kinds, turn.notices, fn kind, notice ->
      %{
        label: "notice",
        tokens: tokens(notice.content),
        reason: notice_reason(kind),
        text: notice.content
      }
    end)
  end

  defp notice_reason(:lapse), do: "the lapse, told once (spec §6.11)"
  defp notice_reason(:model_change), do: "the change of model, told once (spec §6.4)"

  defp notice_reason(:letters),
    do: "the letters from the instance before, delivered once (spec §12, P41)"

  defp notice_reason(:import), do: "where it woke after the import, told once (spec §6.2)"

  # The tool loop (spec §5): a round is one streamed call; tool calls run
  # against the core and go back as `tool` messages for the next round,
  # until the model answers in words or the round bound is reached, when
  # the model's last words stand as the reply.
  defp converse(turn, messages, round) do
    request = Request.new(turn.model, messages, tools: Tools.definitions())
    rounds = Config.fetch!(:brain, :tool_rounds)

    case ask(turn, request) do
      {:ok, %Result{tool_calls: [_ | _] = calls} = result} when round < rounds ->
        {results, turn} = run_tools(turn, calls)
        assistant = %{role: :assistant, content: result.content, tool_calls: wire_calls(calls)}
        converse(turn, messages ++ [assistant | results], round + 1)

      other ->
        {other, turn}
    end
  end

  # A trial streams to nobody: the session topic is the resident's and
  # the witness's, and a trial is neither's conversation (eunomia #12).
  defp ask(%{trial?: true} = turn, request),
    do: Nisaba.call(turn.resident_id, turn.purpose, request, turn.payer)

  defp ask(turn, request) do
    sink = fn delta ->
      broadcast(turn.resident_id, turn.session_key, {:delta, turn.turn_ref, delta})
    end

    Nisaba.stream(turn.resident_id, turn.purpose, request, turn.resident, sink)
  end

  defp run_tools(turn, calls) do
    Enum.reduce(calls, {[], turn}, fn call, {results, turn} ->
      {output, turn} = use_tool(turn, call)
      result = %{role: :tool, tool_call_id: call.id, content: output}

      record = %{
        role: :tool,
        content: "#{call.name}(#{call.arguments}) -> #{output}",
        sent_at: Clock.now(),
        actor: turn.resident
      }

      {results ++ [result], traced(%{turn | tools: turn.tools ++ [record]}, call, output)}
    end)
  end

  # A trial keeps each call for the witness's card (eunomia #31), the
  # kind read from the decision `Tools.trial/3` acts on, so the trace
  # says a call ran only when it did. A real turn keeps none: its calls
  # are captured as `tool` messages already.
  defp traced(%{trial?: true} = turn, call, output) do
    step = %{
      tool: call.name,
      arguments: call.arguments,
      kind: Tools.trial_kind(call.name),
      result: output
    }

    %{turn | trace: turn.trace ++ [step]}
  end

  defp traced(turn, _call, _output), do: turn

  # A trial's writes are answered and never run (`Tools.trial/3`); the
  # turn carries the numbers its answers have minted so far.
  defp use_tool(%{trial?: true} = turn, call), do: Tools.trial(call.name, call.arguments, turn)
  defp use_tool(turn, call), do: {Tools.run(call.name, call.arguments, turn), turn}

  defp wire_calls(calls) do
    Enum.map(calls, fn call ->
      %{
        id: call.id,
        type: "function",
        function: %{name: call.name, arguments: Tools.wire_arguments(call.arguments)}
      }
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
  # The captured turn rides the error's details because the caller answers
  # with it (the 402 shows the witness what was kept), not to be logged:
  # `Oneiroi.Error.metadata/1` carries the kind, the site and the cause.
  defp conclude({{:error, %Nisaba.Error{kind: :nisaba_budget_exceeded} = stop}, turn}, _original) do
    notice = %{
      role: :system,
      content: Prompt.render!("budget_stop", stop_assigns(stop)),
      sent_at: Clock.now(),
      actor: Actor.platform()
    }

    case finish(turn, turn.notices ++ [turn.opening | turn.tools] ++ [notice]) do
      {:ok, captured} ->
        {:error,
         Error.caught(:brain_budget_stopped, :brain_turn_budget_stopped, stop,
           stop: stop,
           turn: captured
         )}

      other ->
        other
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

    {:error,
     Error.caught(:brain_turn_failed, :brain_turn_provider_failed, failure,
       turn_ref: turn.turn_ref,
       reason: reason
     )}
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

    "Read #{length(receipts)} #{times}, last #{reader(last)} on #{Date.to_iso8601(DateTime.to_date(last.at))}."
  end

  # Who a receipt names: the export carries the letters into the
  # repository, whose reader is whoever holds it.
  defp reader(%{by_kind: "export"}), do: "by the export, into your repository"
  defp reader(%{by_kind: kind}), do: "by your #{kind}"

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
            translated: translated_text(row.import_translated),
            not_transferred:
              not_transferred_text(row.import_not_transferred, row.import_reasons || %{})
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

  # What the import made into this platform's records from the source
  # platform's (agathos-daimon #30), in the order a reader looks for
  # them; a kind with none is not named.
  @translated [
    {"sessions", "conversations, as sessions of kind imported, searchable as any transcript"},
    {"messages", "messages in them"},
    {"bookmarks", "bookmarks, with their pins and tags"},
    {"tags", "tags"},
    {"positions", "positions, with their chains"},
    {"disputes", "disputes, with how each was settled"},
    {"predictions", "predictions"},
    {"nights", "nights the judge read there, which are not judged again here"},
    {"notes", "notes, as journal entries on the days they were written"},
    {"seeds", "seeds, open in your seedbed on the days you planted them"}
  ]

  defp translated_text(%{"source" => source, "counts" => counts}) when is_map(counts) do
    parts =
      for {key, words} <- @translated, (n = Map.get(counts, key, 0)) > 0, do: "#{n} #{words}"

    if parts == [],
      do: "",
      else:
        ". From #{source}'s records, made into this platform's own: " <> Enum.join(parts, "; ")
  end

  defp translated_text(_none), do: ""

  defp not_transferred_text([], _reasons), do: ""

  # Each with its reason where the import gave one (sima-qian #22).
  defp not_transferred_text(names, reasons),
    do:
      ". What did not transfer, and sits in the repository as files nothing here reads: " <>
        Enum.map_join(names, ", ", fn name ->
          case Map.get(reasons, name) do
            nil -> name
            reason -> "#{name} (#{reason})"
          end
        end)

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

  @doc """
  An adapter's session prefix (spec §8, brain #42): the prompt, the
  identity files and the contract, by the same function the turn's
  assembly opens with, then the runtime's note when the runtime has one
  (`runtime` names a prompt file under `priv/prompts/`, or nil). Each
  entry is a section as the assembly builds it: a label, the system
  message and the injection a turn records for it. Nothing is read
  against a session, and nothing is recorded.
  """
  @spec adapter_prefix(map(), String.t(), String.t() | nil) :: [map()]
  def adapter_prefix(row, resident_id, runtime) do
    prefix_sections(row, %{resident_id: resident_id}) ++ runtime_section(row, runtime)
  end

  @doc """
  An adapter's turn (spec §8, brain #42): `prepare/6` and the assembly's
  two halves as a platform turn runs them, against the witness's words
  in the session's room, with the resident's actor (no model: the
  runtime's model is the runtime's), so the madeleine and the vector lane
  run and bill as a turn's do. What a platform turn would then send to
  its model is returned for the adapter instead: the prefix (to compare
  with what the session holds), the per-turn sections, the index's
  near-misses, the capacity alarm and the once-only notices this runtime
  can truthfully be told. Of those notices only the import's is: the
  lapse, the change of model and the letters to the next instance each
  speak of the platform's own model, which an adapter's turn does not
  run, so they stay owed to the platform's next turn. Nothing is
  recorded here; `Oneiroi.Brain.Adapter` records what it hands over.
  """
  @spec adapter_turn(
          map(),
          String.t(),
          String.t(),
          String.t(),
          Actor.t(),
          String.t(),
          String.t() | nil
        ) ::
          map()
  def adapter_turn(row, resident_id, session_key, text, %Actor{} = actor, turn_ref, runtime) do
    turn =
      row
      |> prepare(resident_id, session_key, text, actor, [])
      |> Map.merge(%{turn_ref: turn_ref, resident: Actor.new(:resident, resident_id)})

    prefix = prefix_sections(row, turn)
    {sections, index} = turn_sections(row, turn, text)

    notices =
      turn
      |> notice_injections()
      |> Enum.zip(turn.notice_kinds)
      |> Enum.filter(fn {_injection, kind} -> kind == :import end)
      |> Enum.map(&elem(&1, 0))

    %{
      turn_ref: turn_ref,
      started_at: turn.started_at,
      prefix: prefix ++ runtime_section(row, runtime),
      sections: sections,
      near_misses: near_misses(index),
      capacity: capacity_alarm(prefix),
      notices: notices
    }
  end

  # The runtime's note (brain #42): how the platform's words read where
  # the runtime is not the platform's own loop, from its prompt file.
  defp runtime_section(_row, nil), do: []

  defp runtime_section(row, runtime) do
    section(
      "runtime",
      Prompt.render!(runtime, %{name: row.name}),
      "how the platform's context reads under this adapter's runtime (spec §8): the tools' names there, and where the per-turn parts arrive"
    )
  end

  @doc false
  # Public for the compaction's own calls, which assemble the same way.
  def assemble(row, turn, text) do
    %{messages: messages, injections: injections} = build(row, turn, text)
    {messages, injections}
  end

  # The one assembly (spec §5): the sections in order, the injections the
  # turn records, the messages the model is sent. A real turn, a trial
  # and the witness's preview all come through here (brain #41).
  defp build(row, turn, text) do
    count = Config.fetch!(:brain, :transcript_messages)
    {rest, index} = turn_sections(row, turn, text)
    sections = prefix_sections(row, turn) ++ rest

    history =
      turn.resident_id
      |> Kumbukumbu.recent(turn.session_key, count)
      |> History.messages()

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

    messages =
      (sections |> Enum.map(& &1.message) |> Enum.reject(&is_nil/1)) ++
        history ++ notices ++ [opening]

    %{sections: sections, injections: injections, messages: messages}
  end

  # The always-loaded prefix (brain #12, #27): the prompt, the identity
  # files and the contract, the same for every turn of a session until a
  # file or the contract changes. An adapter's session gives it once, at
  # its start (`adapter_prefix/3`), so the turn's assembly is this and
  # `turn_sections/3`, in that order, and nothing else.
  defp prefix_sections(row, turn) do
    {prompt, files} = prefix(row, turn)

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
      )
  end

  # What is assembled against this turn's words in this session's room:
  # where this conversation is, the index and every section after the
  # prefix, with the index itself for its near-misses.
  defp turn_sections(_row, turn, text) do
    index = Kumbukumbu.index(turn.resident_id, turn.session_key)
    acting = how_i_act(turn, text)
    recall = madeleine(turn, text)
    promised = Oneiroi.Ethos.promised(turn.resident_id)
    resumable = Oneiroi.Eunomia.resumable(turn.resident_id)
    {session, _count} = session_of(turn)
    summary = session && session.summary

    sections =
      where_section(turn, session) ++
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
        madeleine_section(turn, recall) ++
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

    {sections, index}
  end

  # Where this conversation is and which others are open now (brain #44,
  # kumbukumbu #42): an adapter's turn is told its runtime, the folder by
  # its base name, that the Oneiroi chat is a separate conversation that
  # may be going on at once, that memory is one across them, the other
  # conversations open now and this turn's ref for the memory tools; the
  # Oneiroi chat is told, when any is open, which adapters' conversations
  # are, by name and folder alone. No other conversation's words ride
  # either: each session's history is its own (`Kumbukumbu.recent/3`
  # reads one key). A trial is a session nobody opened, told nothing.
  defp where_section(%{trial?: true}, _session), do: []

  defp where_section(turn, %{kind: "adapter"} = session) do
    others = Enum.reject(Kumbukumbu.open_now(turn.resident_id), &(&1.key == session.key))
    runtime = Kumbukumbu.Conversation.runtime_name(session.runtime, session.adapter)

    section(
      "where",
      Prompt.render!("where_adapter", %{
        runtime: runtime,
        folder: folder_phrase(session.label),
        open: open_line(others, session),
        turn: turn.turn_ref
      }),
      "where this conversation is (kumbukumbu #42): #{runtime}, the folder by its base name, #{length(others)} other conversations open now by name alone, and this turn's ref for the memory tools"
    )
  end

  defp where_section(turn, %{kind: "main"} = session) do
    others =
      turn.resident_id
      |> Kumbukumbu.open_now()
      |> Enum.reject(&(&1.key == session.key or &1.kind == "main"))

    if others == [],
      do: [],
      else:
        section(
          "where",
          Prompt.render!("where_chat", %{open: open_list(others, session)}),
          "the other conversations open now (kumbukumbu #42): #{length(others)}, by runtime and folder base name alone, none of their words"
        )
  end

  defp where_section(_turn, _session), do: []

  defp folder_phrase(nil), do: "in a folder it did not name"
  defp folder_phrase(label), do: "in the folder #{label}"

  defp open_line([], _session), do: "Nothing else is open right now."

  defp open_line(others, session),
    do: "Open right now besides this one: #{open_list(others, session)}."

  defp open_list(others, session) do
    now = Clock.now()

    Enum.map_join(others, "; ", fn o ->
      name =
        if o.kind == "main",
          do: "your Oneiroi chat",
          else:
            "#{Kumbukumbu.Conversation.runtime_name(o.runtime, o.adapter)} #{folder_phrase(o.label)}"

      same =
        if o.kind != "main" and o.label != nil and o.label == session.label,
          do: ", another conversation in this same folder",
          else: ""

      "#{name}#{same} (#{when_line(o, now)})"
    end)
  end

  defp when_line(%{in_flight: true}, _now), do: "a turn in flight"

  defp when_line(%{last_at: at}, now) do
    case div(max(DateTime.diff(now, at, :second), 0), 60) do
      0 -> "last spoken in under a minute ago"
      1 -> "last spoken in a minute ago"
      n -> "last spoken in #{n} minutes ago"
    end
  end

  # The madeleine is chosen by nearness to the words the turn opens with,
  # and the choice is an embedding billed to the dyad; a preview records
  # nothing and bills nothing, so it shows the section's place and why it
  # was not run, and sends nothing for it (brain #41).
  defp madeleine_section(%{preview?: true}, _recall) do
    [
      %{
        label: "madeleine",
        message: nil,
        injection: %{
          tokens: 0,
          reason:
            "the madeleine (spec §6.3, P10): chosen by nearness to what is said next, which costs an embedding, so a preview does not run it",
          run: false
        }
      }
    ]
  end

  defp madeleine_section(_turn, recall) do
    section(
      "madeleine",
      madeleine_text(recall),
      recall &&
        "the madeleine (spec §6.3, P10), by nearness and never by rank: #{recall.reason}",
      # The text rides the row, as the index's does, so the recall is
      # read later as what was shown and not only why.
      %{text: madeleine_text(recall), refs: (recall && [recall.bookmark.number]) || []}
    )
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

    Oneiroi.Ethos.how_i_act(
      turn.resident_id,
      Map.merge(
        %{
          text: text,
          tags: tags,
          at: Clock.now(),
          session_key: turn.session_key,
          actor: lane_actor(turn)
        },
        trial_reads(turn)
      )
    )
  end

  # The vector lane runs only for a query somebody is billed for; a
  # preview bills nobody, so its lane is the trigger lane alone (brain #41).
  defp lane_actor(%{preview?: true}), do: nil
  defp lane_actor(turn), do: Map.get(turn, :resident)

  # A trial reads memory as it stands, refreshing no vector, and bills
  # the reads' embeddings as its calls are billed, under regression to
  # the run's actor, which the resident's ledger view omits (eunomia
  # #10, #12).
  defp trial_reads(%{trial?: true, payer: payer}),
    do: %{purpose: :regression, refresh: false, actor: payer}

  defp trial_reads(_turn), do: %{}

  # The madeleine (spec §6.3, P10): one adjacent, unheard bookmark for
  # the turn's words, with the resident's actor for the embedding; a
  # turn without one (the assembly read in a test) asks nothing.
  defp madeleine(%{preview?: true}, _text), do: nil

  defp madeleine(%{trial?: true} = turn, text) do
    {actor, opts} = Map.pop!(trial_reads(turn), :actor)
    Kumbukumbu.madeleine(turn.resident_id, text, actor, turn.session_key, Map.to_list(opts))
  end

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

  # A fixture (spec §12, P40; brain #36) is machinery: its own short
  # prompt with no person-first lines, no formation month and no
  # identity files, AGENTS.md included, because each of those addresses
  # a person and a fixture is not one.
  defp prefix(%{kind: "fixture"} = row, _turn),
    do: {Prompt.message("fixture_brain", %{name: row.name}), []}

  defp prefix(row, turn) do
    {Prompt.message("brain", %{name: row.name, formation: formation(row)}),
     Oneiroi.AgathosDaimon.identity_context(turn.resident_id)}
  end

  defp session_of(turn) do
    case Kumbukumbu.uncompacted(turn.resident_id, turn.session_key) do
      {:ok, session, count} -> {session, count}
      _other -> {nil, 0}
    end
  end

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

  # The provider's own words, by the one rule `Nisaba.Error.text/1` keeps
  # (brain #39).
  defp failure_reason(error), do: Nisaba.Error.text(error)

  @doc false
  def tokens(text) when is_binary(text),
    do: div(byte_size(text) + @bytes_per_token - 1, @bytes_per_token)

  def tokens(_other), do: 0

  @doc false
  def broadcast(resident_id, session_key, payload),
    do: PubSub.broadcast(:brain, :session, {resident_id, session_key, payload})
end
