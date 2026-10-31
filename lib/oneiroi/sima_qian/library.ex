defmodule Oneiroi.SimaQian.Library do
  @moduledoc """
  The library port: how an import hands the repository's files to the
  library without this system depending on it, since the library
  depends on records for the repository's path (seshat #12). The
  implementation is named in `SIMA_QIAN_LIBRARY` and read at the call,
  as the schedule's wake and the library's figures are.
  """

  @doc "Adopts every file under the kinds' folders that no document registers, then runs the index once."
  @callback adopt_all(resident_id :: String.t(), actor :: Oneiroi.Actor.t()) ::
              {:ok, %{adopted: [String.t()], skipped: [String.t()], indexed: boolean()}}
              | {:error, term()}

  @doc "Adds journal entries (`%{day, kind, text}`) an import carried from another platform's notes, rendering each day once (sima-qian #19)."
  @callback import_journal(
              resident_id :: String.t(),
              entries :: [map()],
              actor :: Oneiroi.Actor.t()
            ) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc "The kinds' folders: what an import counts as transferred."
  @callback folders() :: [String.t()]
end
