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

  Three endings. A reply, refusal included, is captured as an ordinary
  turn, with each tool call the model made captured as a `tool` message
  before it. A budget stop captures the steward's message and an honest
  notice as a system message, which is how both parties see it in the
  same place. A provider failure captures nothing and records a capture
  failure the steward can mark lost.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Files
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Brain.Compaction
  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Nisaba.Provider.{Request, Result}

  @bytes_per_token 4

  @doc "Runs the turn; see the moduledoc for its three endings."
  @spec run(String.t(), String.t(), String.t(), Actor.t()) :: {:ok, map()} | {:error, term()}
  def run(resident_id, session_key, text, %Actor{} = steward) when is_binary(text) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> run_for(row, resident_id, session_key, text, steward)
      :error -> {:error, :no_such_resident}
    end
  end

  defp run_for(row, resident_id, session_key, text, steward) do
    turn_ref = Kumbukumbu.turn_ref()
    started_at = Clock.now()
    model = Config.fetch!(:brain, :chat_model)
    resident = Actor.new(:resident, resident_id, model)

    turn = %{
      resident_id: resident_id,
      session_key: session_key,
      turn_ref: turn_ref,
      started_at: started_at,
      model: model,
      resident: resident,
      user: %{role: :user, content: text, sent_at: started_at, actor: steward},
      injections: [],
      tools: []
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

    case Nisaba.stream(turn.resident_id, :chat, request, turn.resident, sink) do
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

    finish(turn, [turn.user | turn.tools] ++ [reply])
  end

  # A budget stop: the message and an honest notice, kept where both read.
  defp conclude({{:error, %Nisaba.Error{kind: :nisaba_budget_exceeded} = stop}, turn}, _original) do
    notice = %{
      role: :system,
      content: Prompt.render!("budget_stop", stop_assigns(stop)),
      sent_at: Clock.now(),
      actor: Actor.platform()
    }

    case finish(turn, [turn.user | turn.tools] ++ [notice]) do
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
      broadcast(resident_id, key, {:turn, ref, captured})
      {:ok, captured}
    end
  end

  @doc false
  # Public for the compaction's own calls, which assemble the same way.
  def assemble(row, turn, text) do
    prompt = Prompt.message("brain", %{name: row.name, formation: formation(row)})
    files = identity_files(turn.resident_id, row)
    index = Kumbukumbu.index(turn.resident_id)
    acting = how_i_act(turn, text)
    count = Config.fetch!(:brain, :transcript_messages)
    {session, _count} = session_of(turn)

    history =
      turn.resident_id
      |> Kumbukumbu.recent(turn.session_key, count)
      |> Enum.map(&history_message/1)

    index_message = %{role: :system, content: index.text}
    acting_messages = if acting.count > 0, do: [%{role: :system, content: acting.text}], else: []
    summary = session && session.summary
    summary_messages = if summary, do: [%{role: :system, content: summary}], else: []

    injections =
      [
        %{
          label: "prompt",
          tokens: tokens(prompt.content),
          reason:
            "the brain's prompt file with the resident's name, estimated at four bytes a token"
        }
        | Enum.map(files, fn {name, content} ->
            %{
              label: name,
              tokens: tokens(content),
              reason:
                "the identity file as last written (spec §6.2), estimated at four bytes a token"
            }
          end)
      ] ++
        [
          %{
            label: "index",
            tokens: index.tokens,
            reason:
              "the bookmark index under #{Config.fetch!(:kumbukumbu, :index_tokens)} tokens: #{length(index.included)} listed, #{index.left_out} left out",
            text: index.text,
            refs: index.included
          }
        ] ++
        if(acting.count > 0,
          do: [
            %{
              label: "behaviours",
              tokens: tokens(acting.text),
              reason:
                "how I act: #{acting.count} behaviours whose trigger this situation matched (the steward's words, the conversation's tags, the time of day), with their scores and enacting turns",
              refs: acting.numbers
            }
          ],
          else: []
        ) ++
        if(summary,
          do: [
            %{
              label: "summary",
              tokens: tokens(summary),
              reason:
                "the compaction summary covering this session through store sequence #{session.compacted_through}"
            }
          ],
          else: []
        ) ++
        [
          %{
            label: "transcript",
            tokens: history |> Enum.map(&tokens(&1.content)) |> Enum.sum(),
            reason:
              "the last #{length(history)} messages of this session since its compaction, of at most #{count}, estimated at four bytes a token"
          }
        ]

    file_messages =
      Enum.map(files, fn {name, content} ->
        %{role: :system, content: "# " <> name <> "\n\n" <> content}
      end)

    messages =
      [prompt | file_messages] ++
        [index_message | acting_messages] ++
        summary_messages ++ history ++ [%{role: :user, content: text}]

    {messages, injections}
  end

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

  # The stable prefix (spec §5): the identity files in a fixed order, then
  # the build-owned AGENTS.md, so the cached prefix is the same from turn
  # to turn until a file changes.
  defp identity_files(resident_id, row) do
    written = resident_id |> Oneiroi.AgathosDaimon.files() |> Map.new(&{&1.name, &1.content})

    ordered =
      for name <- Oneiroi.AgathosDaimon.identity_files(),
          content = Map.get(written, name),
          do: {name, content}

    ordered ++ [{"AGENTS.md", Files.agents_md(row)}]
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

  defp history_message(%{role: role, content: content}) do
    %{role: role |> String.to_existing_atom(), content: content}
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
