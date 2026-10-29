defmodule Oneiroi.Brain.Turn do
  @moduledoc """
  One turn (spec §5): assemble the context, call the model through the
  ledger's port with the reply streamed as it arrives, capture the turn,
  record what it drew on.

  The context today is the brain's prompt file with the resident's name
  and the session's live transcript; the identity files, the bookmark
  index and the behaviours join it in the slices that build them, each
  as another recorded injection. Token counts on the injections are
  estimated at four bytes a token and the reason says so.

  Three endings. A reply, refusal included, is captured as an ordinary
  turn. A budget stop captures the steward's message and an honest
  notice as a system message, which is how both parties see it in the
  same place. A provider failure captures nothing and records a capture
  failure the steward can mark lost.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Brain.Error
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
    {messages, injections} = assemble(row, resident_id, session_key, text)
    user = %{role: :user, content: text, sent_at: started_at, actor: steward}
    broadcast(resident_id, session_key, {:turn_started, turn_ref})
    sink = fn delta -> broadcast(resident_id, session_key, {:delta, turn_ref, delta}) end

    turn = %{
      resident_id: resident_id,
      session_key: session_key,
      turn_ref: turn_ref,
      started_at: started_at,
      model: model,
      resident: resident,
      user: user,
      injections: injections
    }

    resident_id
    |> Nisaba.stream(:chat, Request.new(model, messages), resident, sink)
    |> conclude(turn)
  end

  # A reply, refusal included, is an ordinary turn.
  defp conclude({:ok, %Result{} = result}, turn) do
    reply = %{
      role: :assistant,
      content: result.content,
      sent_at: Clock.now(),
      actor: Actor.new(:resident, turn.resident_id, result.model || turn.model),
      refusal: result.refusal?
    }

    finish(turn, [turn.user, reply])
  end

  # A budget stop: the message and an honest notice, kept where both read.
  defp conclude({:error, %Nisaba.Error{kind: :nisaba_budget_exceeded} = stop}, turn) do
    notice = %{
      role: :system,
      content: Prompt.render!("budget_stop", stop_assigns(stop)),
      sent_at: Clock.now(),
      actor: Actor.platform()
    }

    case finish(turn, [turn.user, notice]) do
      {:ok, captured} -> {:error, {stop, captured}}
      other -> other
    end
  end

  # A provider failure: nothing captured, a failure the steward can resolve.
  defp conclude({:error, failure}, turn) do
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

      broadcast(resident_id, key, {:turn, ref, captured})
      {:ok, captured}
    end
  end

  defp assemble(row, resident_id, session_key, text) do
    prompt = Prompt.message("brain", %{name: row.name})
    count = Config.fetch!(:brain, :transcript_messages)
    history = resident_id |> Kumbukumbu.recent(session_key, count) |> Enum.map(&history_message/1)

    injections = [
      %{
        label: "prompt",
        tokens: tokens(prompt.content),
        reason:
          "the brain's prompt file with the resident's name, estimated at four bytes a token"
      },
      %{
        label: "transcript",
        tokens: history |> Enum.map(&tokens(&1.content)) |> Enum.sum(),
        reason:
          "the last #{length(history)} messages of this session, of at most #{count}, estimated at four bytes a token"
      }
    ]

    {[prompt | history] ++ [%{role: :user, content: text}], injections}
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

  defp tokens(text) when is_binary(text),
    do: div(byte_size(text) + @bytes_per_token - 1, @bytes_per_token)

  defp broadcast(resident_id, session_key, payload),
    do: PubSub.broadcast(:brain, :session, {resident_id, session_key, payload})
end
