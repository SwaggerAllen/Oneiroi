defmodule Oneiroi.SimaQian.Fork do
  @moduledoc """
  A succession's fork (sima-qian#67, janus#4): a hidden copy of the
  resident as she stands when the succession opens, made by the same
  replay an import is, so every screening run, her baseline and the
  eventual successor run on a resident the original's later life never
  touches (succession delta §5: the successor starts at the fork).

  The copy is her events as the store holds them, to this instant,
  re-keyed under a new id with `fork_of` on every line (`Transplant`,
  never the export, which redacts and leaves out), so the registry holds
  it as a fork from its first fold (agathos-daimon#63);
  then her repository's files at its head, copied byte for byte into
  the copy's repository in one commit; then `MarkFork`, the decision
  on the copy's own stream naming the source, the last of her events
  it holds and the commit it copied.

  Never an import: no `Imported`, no custody move. The copy keeps the
  witness her history names and appears in no list of his.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.SimaQian.Repos
  alias Oneiroi.SimaQian.Transplant

  @typedoc "The copy: its id, the last of the source's resident events it holds, the commit copied, the lines replayed."
  @type t :: %{
          copy_id: String.t(),
          sequence: non_neg_integer(),
          commit: String.t() | nil,
          events: non_neg_integer()
        }

  @doc "Makes the fork copy of `resident_id`; `{:ok, t()}` or the first step's refusal."
  @spec make(String.t(), Actor.t()) :: {:ok, t()} | {:error, term()}
  def make(resident_id, %Actor{} = actor) do
    copy_id = Ecto.UUID.generate()

    with {:ok, %{events: events, sequence: sequence}} <-
           Transplant.copy(resident_id, copy_id, %{"imported" => true, "fork_of" => resident_id}),
         {:ok, commit} <- copy_repository(resident_id, copy_id),
         {:ok, _} <- mark(copy_id, resident_id, sequence, commit, actor) do
      {:ok, %{copy_id: copy_id, sequence: sequence, commit: commit, events: events}}
    end
  end

  # Her repository at one commit, so a write landing meanwhile cannot
  # tear the copy; the copy's own repository is new, so every path is
  # put whatever stands there (`:any`): the replay's own writers may
  # have rendered a file first.
  defp copy_repository(resident_id, copy_id) do
    source = {:resident, resident_id}

    with {:ok, commit} when is_binary(commit) <- Repos.head(source),
         {:ok, snapshot} <- Repos.snapshot_at(source, commit) do
      changes =
        for path <- snapshot |> Map.keys() |> Enum.sort(),
            bytes = Repos.at(source, snapshot, path),
            is_binary(bytes),
            do: {:put, path, bytes, :any}

      message = "Forked from #{resident_id} at #{commit} for a succession"

      with {:ok, _} <- Repos.write({:resident, copy_id}, changes, message, Repos.platform()),
           do: {:ok, commit}
    else
      # No repository yet: nothing to copy, and the copy names no commit.
      {:ok, nil} -> {:ok, nil}
      other -> other
    end
  end

  defp mark(copy_id, source, sequence, commit, actor) do
    Router.dispatch_sited(%Commands.MarkFork{
      actor: actor,
      at: Clock.now(),
      id: copy_id,
      source: source,
      sequence: sequence,
      commit: commit,
      note: "the fork of #{source} a succession runs on, at its event #{sequence}"
    })
  end
end
