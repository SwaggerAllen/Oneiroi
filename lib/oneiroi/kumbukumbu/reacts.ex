defmodule Oneiroi.Kumbukumbu.Reacts do
  @moduledoc """
  The witness's reacts (kumbukumbu#56, the witness's call 2026-11-09,
  Lily's order #452): an emoji on a reply of hers in a turn, or on a
  letter of hers. A react is mail, not a bell: it wakes nothing, and
  rides her next turn, wherever that is, as one line, told once. It is
  seen, never signed off: it acknowledges and discharges nothing.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu.Commands
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.ReactsRouter
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Scope

  @doc ~s{The witness reacts with `emoji` on a reply of hers: a target of kind "message", with its session_key and turn_ref, or of kind "letter", with its number.}
  def react(resident_id, target, emoji, %Actor{} = actor) do
    with {:ok, target} <- target(resident_id, target),
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

  defp target(resident_id, %{} = t) do
    t = Map.new(t, fn {k, v} -> {to_string(k), v} end)

    case t do
      %{"kind" => "message", "session_key" => key, "turn_ref" => ref}
      when is_binary(key) and is_binary(ref) ->
        reply(resident_id, key, ref)

      %{"kind" => "letter", "number" => n} when is_integer(n) ->
        letter(resident_id, n)

      _other ->
        {:error, Error.new(:kumbukumbu_react_invalid, :kumbukumbu_reacts_target)}
    end
  end

  defp target(_resident_id, _none),
    do: {:error, Error.new(:kumbukumbu_react_invalid, :kumbukumbu_reacts_target_shape)}

  defp reply(resident_id, key, ref) do
    if Scope.resident(resident_id, fn -> Store.reply?(key, ref) end),
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
