defmodule Oneiroi.Sunna.Wakes do
  @moduledoc """
  The wake log (sunna#71; Lily's `design/wake-mail-visibility.md` §2
  Gaps 1 and 4): every wake that goes to a resident is manifested, with
  its channel and the envelopes it carried (never what the turn said),
  and read when its note goes into her turn. A wake declined (she was
  not active, or in her quiet hours) or never run stays unread, so the
  gap shows. Both the witness and the resident read the same rows.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Repo
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Router
  alias Oneiroi.Sunna.Store.Wake

  @doc """
  Manifests a wake: its channel, its causes (each a map with a `kind`),
  and, as options, the household it is for and whether it was delivered
  (false for a mention banked unwoken). Answers its id.
  """
  def manifest(resident_id, channel, causes, opts \\ []) do
    wake_id = Keyword.get_lazy(opts, :wake_id, &Ecto.UUID.generate/0)

    command = %Commands.ManifestWake{
      actor: Keyword.get(opts, :actor, Actor.platform()),
      at: Clock.now(),
      id: resident_id,
      wake_id: wake_id,
      channel: channel,
      causes: Enum.map(causes, &stringify/1),
      household_id: Keyword.get(opts, :household_id),
      delivered: Keyword.get(opts, :delivered, true)
    }

    with {:ok, _} <- dispatch(command), do: {:ok, wake_id}
  end

  @doc "Marks a wake read: its note went into her turn. Nothing for nil, or a wake read already."
  def read(_resident_id, nil), do: :ok

  def read(resident_id, wake_id) do
    command = %Commands.ReadWake{
      actor: Actor.platform(),
      at: Clock.now(),
      id: resident_id,
      wake_id: wake_id
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "Manifests a wake and marks it read at once: a wake that runs as it is made (a letter's, free time's)."
  def run(resident_id, channel, causes, opts \\ []) do
    with {:ok, wake_id} <- manifest(resident_id, channel, causes, opts),
         :ok <- read(resident_id, wake_id),
         do: {:ok, wake_id}
  end

  @doc "The wakes of these residents, newest first, at most `limit`: rows as the log reads them."
  def list(resident_ids, limit \\ 100) do
    Scope.platform(fn ->
      Repo.all(
        from(w in Wake,
          where: w.resident_id in ^resident_ids,
          order_by: [desc: w.manifested_at],
          limit: ^limit
        )
      )
    end)
    |> Enum.map(&row/1)
  end

  defp row(%Wake{} = w),
    do: %{
      resident_id: w.resident_id,
      wake_id: w.wake_id,
      household_id: w.household_id,
      channel: w.channel,
      causes: Map.get(w.causes || %{}, "list", []),
      delivered: w.delivered,
      at: w.manifested_at,
      read_at: w.read_at
    }

  defp stringify(%{} = cause), do: Map.new(cause, fn {k, v} -> {to_string(k), v} end)

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, _} = ok ->
        ok

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:sunna_wake_failed, :sunna_wakes_dispatch, reason)}
    end
  end
end
