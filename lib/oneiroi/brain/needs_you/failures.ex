defmodule Oneiroi.Brain.NeedsYou.Failures do
  @moduledoc """
  Turns that failed, in the bell (brain#88; the witness, 2026-11-13:
  "errors for scheduled messages and for direct messages [should]
  surface in the ui, especially if openrouter is out of tokens because
  that requires user action"). A turn the provider refused or that broke
  is recorded as a capture failure; a scheduled one (a check-in, free
  time, a round) has no message of his waiting on it, so until now it
  showed nowhere.

  Every open failure of the last `@days` days is an entry. Those the
  provider refused for credit (a 402) fold into one `provider_credits`
  entry, since one act of his settles them all; every other failure is
  its own `turn_failed` entry with the provider's reason and the
  conversation it was in. Dismissing resolves them (`marked_lost`), and
  the bell's push tells his devices like any other entry.
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Kumbukumbu

  # Older open failures are history, not news: they stay readable on the
  # capture-failures route and out of the bell.
  @days 7

  @impl true
  def stages,
    do: [%{kind: "provider_credits", screen: "settings"}, %{kind: "turn_failed", screen: "chat"}]

  @impl true
  def entries(resident_id) do
    since = DateTime.add(Clock.now(), -@days * 86_400)
    scope = {:resident, resident_id}

    failures =
      scope
      |> Kumbukumbu.failures()
      |> Enum.filter(
        &(&1.resident_id == resident_id and DateTime.compare(&1.failed_at, since) == :gt)
      )

    kinds = Map.new(Kumbukumbu.sessions(scope), &{&1.key, &1.kind})
    {credits, others} = Enum.split_with(failures, &credits?(&1.reason))

    credit_entry(credits) ++ Enum.map(others, &failed(&1, kinds))
  end

  @doc "Whether a failure's reason is the provider refusing for credit."
  @spec credits?(String.t() | nil) :: boolean()
  def credits?(reason) when is_binary(reason),
    do: String.contains?(reason, "402") and String.contains?(String.downcase(reason), "credit")

  def credits?(_reason), do: false

  defp credit_entry([]), do: []

  defp credit_entry([first | _] = all) do
    last = List.last(all)

    [
      %Entry{
        kind: "provider_credits",
        ref: "openrouter",
        since: first.failed_at,
        screen: "settings",
        about: %{
          what: "OpenRouter refused #{length(all)} turn(s) for credit",
          reason: last.reason,
          failures:
            Enum.map(
              all,
              &%{session_key: &1.session_key, turn_ref: &1.turn_ref, failed_at: &1.failed_at}
            )
        }
      }
    ]
  end

  defp failed(f, kinds),
    do: %Entry{
      kind: "turn_failed",
      ref: f.turn_ref,
      since: f.failed_at,
      screen: "chat",
      about: %{
        what: f.reason,
        reason: f.reason,
        session_key: f.session_key,
        conversation: Map.get(kinds, f.session_key)
      }
    }
end
