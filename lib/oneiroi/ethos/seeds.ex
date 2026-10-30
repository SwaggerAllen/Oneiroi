defmodule Oneiroi.Ethos.Seeds do
  @moduledoc """
  The seedbed (spec §6.17, P37): dated, first-person, non-binding
  becomings, the resident's alone to plant, cite, wilt or graduate, and
  the witness's to read. The evidence drawer of the soul file's growth
  path: a seed cites the moments that evidenced it, and graduates by a
  receipted move toward a habit once its citations confirm it across
  the required days, or toward an evaluative kind with no such
  evidence asked. A seed may wilt without ceremony, which is what keeps
  a premature line out of the soul file.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Ethos.Commands
  alias Oneiroi.Ethos.Edge
  alias Oneiroi.Ethos.Error
  alias Oneiroi.Ethos.Store
  alias Oneiroi.Scope

  @doc "Plants a seed in the resident's words; returns its number."
  @spec plant(String.t(), String.t(), Actor.t()) :: {:ok, pos_integer()} | {:error, term()}
  def plant(resident_id, text, %Actor{} = actor) do
    # The blank is refused before a number is minted, so a slip does not
    # burn a citeable number; the aggregate refuses it again regardless.
    with :ok <- resident_only(actor),
         :ok <- text_present(text),
         {:ok, number} <- Oneiroi.AgathosDaimon.mint_id(resident_id, "seed", actor) do
      command = %Commands.PlantSeed{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        text: text
      }

      with {:ok, _} <- Edge.dispatch(command), do: {:ok, number}
    end
  end

  @doc "Wilts an open seed, without ceremony."
  def wilt(resident_id, number, %Actor{} = actor) do
    with :ok <- resident_only(actor) do
      command = %Commands.WiltSeed{actor: actor, at: Clock.now(), id: resident_id, number: number}
      with {:ok, _} <- Edge.dispatch(command), do: :ok
    end
  end

  @doc "Graduates an open seed toward a habit (confirmed across `ETHOS_PROMOTION_CONFIRMATIONS` days) or an evaluative kind, with a note."
  def graduate(resident_id, number, to_kind, to_id, note, %Actor{} = actor) do
    with :ok <- resident_only(actor),
         :ok <- graduation_target(resident_id, to_kind, to_id) do
      command = %Commands.GraduateSeed{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        number: number,
        to_kind: to_kind,
        to_id: to_string(to_id),
        required: Config.fetch!(:ethos, :promotion_confirmations)
      }

      with {:ok, _} <- Edge.dispatch(command), do: :ok
    end
  end

  @doc "The seed cites a moment that evidenced it: a turn (by ref) or a bookmark (by number, which must exist), with what the moment changed (P34) or nil."
  def cite(resident_id, number, kind, target_id, %Actor{} = actor, movement \\ nil) do
    with :ok <- resident_only(actor),
         :ok <- Edge.target_exists(resident_id, kind, target_id),
         {:ok, movement} <- Edge.movement(movement) do
      command = %Commands.CiteSeed{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        target_kind: kind,
        target_id: to_string(target_id),
        movement: movement
      }

      with {:ok, _} <- Edge.dispatch(command), do: :ok
    end
  end

  @doc "Every seed with its citation count and the distinct days it was cited, by number."
  @spec seeds(String.t()) :: [Store.Seed.t()]
  def seeds(resident_id) do
    Scope.resident(resident_id, fn ->
      citations = Enum.group_by(Store.citations("seed"), & &1.number)

      Enum.map(Store.seeds(), fn s ->
        mine = Map.get(citations, s.number, [])

        %{
          s
          | citations: length(mine),
            days: mine |> Enum.map(&DateTime.to_date(&1.at)) |> Enum.uniq() |> length()
        }
      end)
    end)
  end

  # Toward a soul line the target is checked at the edge (a live line by
  # number); toward a position it cannot be, see `Edge.target_exists/3`.
  defp graduation_target(resident_id, "soul", to_id),
    do: Edge.target_exists(resident_id, "soul", to_id)

  defp graduation_target(_resident_id, _to_kind, _to_id), do: :ok

  defp resident_only(%Actor{kind: :resident}), do: :ok
  defp resident_only(%Actor{}), do: {:error, Error.new(:ethos_not_the_resident)}

  defp text_present(text) when is_binary(text) do
    if String.trim(text) == "", do: {:error, Error.new(:ethos_seed_text_invalid)}, else: :ok
  end

  defp text_present(_other), do: {:error, Error.new(:ethos_seed_text_invalid)}
end
