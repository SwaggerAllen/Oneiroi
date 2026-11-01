defmodule Oneiroi.Nisaba.Error do
  @moduledoc "The ledger's boundary failure vocabulary, built from its `errors/0`."
  use Oneiroi.Error, component: __MODULE__ |> Module.split() |> Enum.drop(-1) |> Module.concat()

  @doc """
  A failed call as its reader sees it: the kind, and when the provider
  answered with a status, the status and the provider's own words.

  The provider's words ride `reason:` in the details, and the adapter
  keeps only the error's `message`, never its `metadata`, which is where
  OpenRouter documents putting a moderation hit's flagged input: the
  provider's diagnosis, never the transcript (spec §6.3). One rule for
  every reader. The brain had it (brain #39) after the fixture's refused
  turns showed only `nisaba_request_refused`. A regression card did not,
  and on 2026-11-01 Lily's first run showed that same bare kind on every
  card, for a model id the provider had refused in its own words.
  """
  @spec text(term()) :: String.t()
  def text(%{kind: kind, details: details}) when is_atom(kind) do
    case Keyword.get(details || [], :reason) do
      {:status, status, message} when is_binary(message) ->
        "#{kind}: #{status} #{String.slice(message, 0, 300)}"

      {:status, status, _unparseable} ->
        "#{kind}: #{status}"

      _other ->
        Atom.to_string(kind)
    end
  end

  def text(other), do: other |> Oneiroi.Error.describe() |> inspect()
end
