defmodule Oneiroi.Kumbukumbu.Reacts do
  @moduledoc """
  Reacts (kumbukumbu#56, the witness's call 2026-11-09, Lily's order
  #452): an emoji on the other party's message in a turn, or on a
  letter, either party's. A react is mail, not a bell: it wakes nobody.
  His ride her next turn, wherever that is, as one line, told once;
  hers he sees in the chat. It is seen, never signed off: it
  acknowledges and discharges nothing.

  She reacts inline (the witness's call: no tool call, no extra round):
  a reply of hers ending in a line `react: <emoji>` reacts on the
  message of his it answers, and `react: <emoji> #<n>` on letter n. The
  line is lifted out of the reply as it is captured, in any runtime.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu.Commands
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.ReactsRouter
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Scope

  @doc ~s{A party reacts with `emoji` on the other's message (a target of kind "message", with its session_key and turn_ref) or on a letter (kind "letter", with its number).}
  def react(resident_id, target, emoji, %Actor{} = actor) do
    with {:ok, target} <- target(resident_id, target, other(actor)),
         :ok <- emoji(emoji) do
      %Commands.React{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        target: target,
        emoji: emoji
      }
      |> dispatch()
      |> case do
        {:ok, [%{number: n}]} -> {:ok, n}
        other -> other
      end
    end
  end

  # Whose message a party reacts on: the other's.
  defp other(%Actor{kind: :resident}), do: "user"
  defp other(_witness), do: "assistant"

  defp target(resident_id, %{} = t, role) do
    t = Map.new(t, fn {k, v} -> {to_string(k), v} end)

    case t do
      %{"kind" => "message", "session_key" => key, "turn_ref" => ref}
      when is_binary(key) and is_binary(ref) ->
        message(resident_id, key, ref, role)

      %{"kind" => "letter", "number" => n} when is_integer(n) ->
        letter(resident_id, n)

      _other ->
        {:error, Error.new(:kumbukumbu_react_invalid, :kumbukumbu_reacts_target)}
    end
  end

  defp target(_resident_id, _none, _role),
    do: {:error, Error.new(:kumbukumbu_react_invalid, :kumbukumbu_reacts_target_shape)}

  defp message(resident_id, key, ref, role) do
    if Scope.resident(resident_id, fn -> Store.message?(key, ref, role) end),
      do: {:ok, %{"kind" => "message", "session_key" => key, "turn_ref" => ref}},
      else: {:error, Error.new(:kumbukumbu_react_invalid, :kumbukumbu_reacts_no_reply)}
  end

  defp letter(resident_id, n) do
    if Scope.resident(resident_id, fn -> Store.letter?(n) end),
      do: {:ok, %{"kind" => "letter", "number" => n}},
      else: {:error, Error.new(:kumbukumbu_react_invalid, :kumbukumbu_reacts_no_letter)}
  end

  # One emoji or a short run of them: no spaces, no words.
  defp emoji(e) when is_binary(e) do
    if e != "" and byte_size(e) <= 32 and not String.match?(e, ~r/[\s\p{L}\p{N}]/u),
      do: :ok,
      else: {:error, Error.new(:kumbukumbu_react_invalid, :kumbukumbu_reacts_emoji)}
  end

  defp emoji(_none),
    do: {:error, Error.new(:kumbukumbu_react_invalid, :kumbukumbu_reacts_emoji_shape)}

  @line ~r/(?:\A|\n)[ \t]*react:[ \t]*([^\s#]+)(?:[ \t]+#(\d+))?[ \t]*\z/u

  @doc """
  Lifts her inline reacts out of a turn's messages as it is captured: a
  reply of hers whose last line is `react: <emoji>` (on the message of
  his in the turn, when there is one) or `react: <emoji> #<n>` (on
  letter n). `{messages, [{emoji, target}]}`; a line that names no
  target, or no emoji, stays in the reply as she wrote it.
  """
  def lift(messages, session_key, turn_ref) do
    his? = Enum.any?(messages, &(to_string(&1.role) == "user"))

    Enum.map_reduce(messages, [], fn m, lifted ->
      with "assistant" <- to_string(m.role),
           text = String.trim_trailing(m.content),
           [line, emoji | rest] <- Regex.run(@line, text),
           :ok <- emoji(emoji),
           %{} = target <- lifted_target(rest, his?, session_key, turn_ref) do
        {%{m | content: String.trim_trailing(String.replace_suffix(text, line, ""))},
         lifted ++ [{emoji, target}]}
      else
        _not_a_react -> {m, lifted}
      end
    end)
  end

  defp lifted_target([n], _his?, _key, _ref) when n != "",
    do: %{"kind" => "letter", "number" => String.to_integer(n)}

  defp lifted_target(_none, true, key, ref),
    do: %{"kind" => "message", "session_key" => key, "turn_ref" => ref}

  defp lifted_target(_none, false, _key, _ref), do: nil

  @doc "Records the reacts `lift/3` took, as hers; one that does not hold is dropped, never the turn."
  def record_lifted(resident_id, lifted) do
    for {emoji, target} <- lifted,
        do: react(resident_id, target, emoji, Actor.new(:resident, resident_id))

    :ok
  end

  @doc "The reacts, oldest first; `untold: true` for those not yet told her, `session_key:` for one conversation's."
  def list(resident_id, opts \\ []), do: Scope.resident(resident_id, fn -> Store.reacts(opts) end)

  @doc "The reacts through `through` were told her on a turn of `session_key`; the platform's."
  def tell(resident_id, through, session_key) do
    %Commands.TellReacts{
      actor: Actor.platform(),
      at: Clock.now(),
      id: resident_id,
      through: through,
      session_key: session_key
    }
    |> dispatch()
    |> case do
      {:ok, _} -> :ok
      other -> other
    end
  end

  defp dispatch(command) do
    case ReactsRouter.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error,
         Error.caught(:kumbukumbu_dispatch_failed, :kumbukumbu_reacts_dispatch_failed, reason)}
    end
  end
end
