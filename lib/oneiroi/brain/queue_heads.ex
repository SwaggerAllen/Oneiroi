defmodule Oneiroi.Brain.QueueHeads do
  @moduledoc """
  An artifact's head as the house queue's first guard reads it at
  execution (sunna#80, lily:design/queue-ia §5): the commit that last
  changed what a citation names. Here and not in the queue, since the
  queue sits below the library and the repositories.

  - `house/<slug>:<kind>/<ref>`: the household repository's last commit
    to that path;
  - `<resident>:<kind>/<path>`: that member resident's repository's last
    commit to `<kind>/<path>` (`.md` added when it has no extension);
  - anything else (a PR, an external page): nil, no head the platform
    can read, so the pin named at approval stands alone.

  A citation already pinned (`@<commit>`) names its pin, not a head.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  @doc "The head commit of what `citation` names in this household, or nil."
  @spec head(String.t(), String.t() | nil) :: String.t() | nil
  def head(_household_id, nil), do: nil

  def head(household_id, citation) when is_binary(citation) do
    cond do
      String.starts_with?(citation, "slot:") -> nil
      String.contains?(citation, "@") -> nil
      String.starts_with?(citation, "house/") -> house(household_id, citation)
      true -> resident(household_id, citation)
    end
  end

  @doc "Where a citation points: `:house`, `:resident` (a member resident's file) or `:other`, which the platform cannot read."
  @spec place(String.t(), String.t()) :: :house | :resident | :other
  def place(household_id, citation) do
    cond do
      String.starts_with?(citation, "slot:") -> :other
      String.starts_with?(citation, "house/") -> :house
      resident_slug?(household_id, citation) -> :resident
      true -> :other
    end
  end

  defp resident_slug?(household_id, citation) do
    case String.split(citation, ":", parts: 2) do
      [slug, _rest] -> not is_nil(resident_by_slug(household_id, slug))
      _other -> false
    end
  end

  defp house(household_id, citation) do
    with {:ok, %{path: path}} <- Seshat.house_citation(citation),
         {:ok, [%{sha: sha} | _]} <- SimaQian.household_log(household_id, path, 1) do
      sha
    else
      _ -> nil
    end
  end

  defp resident(household_id, citation) do
    with [slug, rest] <- String.split(citation, ":", parts: 2),
         id when is_binary(id) <- resident_by_slug(household_id, slug),
         {:ok, [%{sha: sha} | _]} <- SimaQian.repository_log(id, path(rest), 1) do
      sha
    else
      _ -> nil
    end
  end

  defp path(rest), do: if(Path.extname(rest) == "", do: rest <> ".md", else: rest)

  defp resident_by_slug(household_id, slug) do
    Enum.find_value(Gaia.household_members(household_id), fn
      %{kind: "resident", id: id} ->
        case AgathosDaimon.fetch(id) do
          {:ok, %{slug: ^slug}} -> id
          _other -> nil
        end

      _witness ->
        nil
    end)
  end
end
