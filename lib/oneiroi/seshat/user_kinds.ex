defmodule Oneiroi.Seshat.UserKinds do
  @moduledoc """
  A resident's own kinds and the system kinds' gates (seshat#51), as both
  parties act on them. A kind's definition lives in its folder as a
  descriptor file (`Kinds.descriptor_name/0`), the truth that travels
  with the repository (the witness, 2026-11-09: "as little as possible
  outside the filesystem"); the table is its projection. Defining a kind
  checks the descriptor against the safe subset, records it, and writes
  the file; loading reads every folder's descriptor back, checks each the
  same way, and records what is new or changed: a descriptor that claims
  what a user kind may not is refused, and the documents under it are
  never touched.
  """

  # sobelow_skip ["Traversal.FileModule"]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Citations
  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Seshat.KindsRouter
  alias Oneiroi.Seshat.Store
  alias Oneiroi.SimaQian

  @doc "Her kinds as both parties read them: every kind with its label and gate, which are hers, and the open and recent gate proposals."
  def list(resident_id) do
    proposals = Scope.resident(resident_id, fn -> Store.kind_gate_proposals() end)
    owned = Map.new(Scope.resident(resident_id, fn -> Store.user_kinds() end), &{&1.kind, &1})

    kinds =
      for k <- Kinds.shelf(resident_id) do
        row = owned[k.kind]

        %{
          kind: k.kind,
          label: k[:label] || k.kind,
          folder: k.folder,
          own: Map.get(k, :user, false),
          approvable: Kinds.approvable?(k),
          gated: k.kind in Kinds.gated_kinds(),
          cites: k.cites,
          created_by: row && row.created_by,
          updated_by: row && row.updated_by
        }
      end

    %{kinds: kinds, proposals: Enum.map(proposals, &proposal/1)}
  end

  defp proposal(p),
    do: %{
      number: p.number,
      kind: p.kind,
      approvable: p.approvable,
      proposed_by: p.proposed_by,
      note: p.note,
      proposed_at: p.proposed_at,
      agree: p.agree,
      answered_by: p.answered_by,
      answer_note: p.answer_note,
      answered_at: p.answered_at
    }

  @doc "Defines or rewrites a kind of hers (seshat#51), either party; the descriptor is checked against the safe subset and written into its folder."
  def define(resident_id, attrs, note, %Actor{} = actor) do
    owned = Scope.resident(resident_id, fn -> Store.user_kinds() end)
    name = to_string(attrs["kind"] || attrs[:kind] || "")
    taken = for k <- owned, k.kind != name, do: k.kind

    with {:ok, descriptor} <- Kinds.user_descriptor(attrs, taken),
         {:ok, _} <- dispatch(define_command(resident_id, descriptor, note, actor)),
         :ok <- write_descriptor(resident_id, descriptor, actor) do
      {:ok, descriptor["kind"]}
    end
  end

  defp define_command(resident_id, descriptor, note, actor),
    do: %Commands.DefineKind{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      kind: descriptor["kind"],
      descriptor: descriptor,
      note: note
    }

  @doc "Moves a system kind's gate (seshat#51): on at once, by either party; off as a proposal the other answers. `{:ok, :moved | :proposed | :already}`."
  def gate(resident_id, kind, approvable, note, %Actor{} = actor) do
    if kind in Kinds.gated_kinds() do
      command = %Commands.ProposeKindGate{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        kind: kind,
        approvable: approvable,
        note: note
      }

      case dispatch(command) do
        {:ok, []} -> {:ok, :already}
        {:ok, [%{__struct__: Oneiroi.Seshat.Events.KindGateMoved} | _]} -> {:ok, :moved}
        {:ok, _proposed} -> {:ok, :proposed}
        other -> other
      end
    else
      {:error, Error.new(:seshat_kind_gate_invalid, :seshat_user_kinds_gate_not_gated)}
    end
  end

  @doc "The other party answers a gate proposal, with a note (seshat#51)."
  def answer(resident_id, number, agree, note, %Actor{} = actor) do
    command = %Commands.AnswerKindGate{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      agree: agree,
      note: note
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc """
  Reads every folder's descriptor back from the repository (an import, a
  hand edit in git) and records each new or changed one that passes the
  safe subset; a system kind's folder is the platform's and is passed
  over. `{:ok, %{loaded: [...], refused: [{folder, reason}]}}`; the
  documents under a refused descriptor are never touched.
  """
  def load(resident_id, %Actor{} = actor) do
    with {:ok, dir} <- SimaQian.repository_dir(resident_id) do
      owned = Map.new(Scope.resident(resident_id, fn -> Store.user_kinds() end), &{&1.kind, &1})

      results =
        for path <- Path.wildcard(Path.join([dir, "*", Kinds.descriptor_name()])),
            folder = path |> Path.dirname() |> Path.basename(),
            is_nil(Kinds.kind_of(folder <> "/x.md")),
            do: {folder, load_one(resident_id, path, owned, actor)}

      {:ok,
       %{
         loaded: for({f, :loaded} <- results, do: f),
         refused: for({f, {:refused, why}} <- results, do: {f, why})
       }}
    end
  end

  defp load_one(resident_id, path, owned, actor) do
    folder = path |> Path.dirname() |> Path.basename()

    with {:ok, text} <- File.read(path),
         {:ok, %{} = attrs} <- Jason.decode(text),
         :ok <- in_its_folder(attrs, folder),
         taken = Map.keys(owned) -- [attrs["kind"]],
         {:ok, descriptor} <- Kinds.user_descriptor(attrs, taken),
         :ok <- record(resident_id, descriptor, owned[descriptor["kind"]], actor) do
      :loaded
    else
      :same -> :same
      {:error, e} -> {:refused, reason(e)}
      _ -> {:refused, "not a descriptor"}
    end
  end

  defp in_its_folder(%{"kind" => folder}, folder), do: :ok

  defp in_its_folder(_attrs, _folder),
    do: {:error, Error.new(:seshat_kind_invalid, :seshat_user_kinds_load_elsewhere)}

  defp record(_resident_id, descriptor, %{descriptor: descriptor}, _actor), do: :same

  defp record(resident_id, descriptor, _row, actor) do
    with {:ok, _} <-
           dispatch(define_command(resident_id, descriptor, "loaded from its folder", actor)),
         do: :ok
  end

  defp reason(%{site: site}), do: to_string(site)
  defp reason(%Jason.DecodeError{}), do: "not valid JSON"
  defp reason(other), do: inspect(other)

  # The descriptor beside the documents it describes, with who wrote it
  # and when (seshat#51): the file is what travels.
  defp write_descriptor(resident_id, descriptor, actor) do
    with {:ok, dir} <- SimaQian.repository_dir(resident_id) do
      folder = Path.join(dir, descriptor["folder"])
      File.mkdir_p!(folder)

      file =
        Map.merge(descriptor, %{
          "updated_by" => to_string(actor.kind),
          "updated_at" => DateTime.to_iso8601(Clock.now())
        })

      File.write!(
        Path.join(folder, Kinds.descriptor_name()),
        Jason.encode!(file, pretty: true) <> "\n"
      )

      :ok
    end
  end

  defp dispatch(command) do
    case KindsRouter.dispatch(command) do
      {:ok, events} ->
        if Enum.any?(events, &match?(%Events.KindDefined{}, &1)),
          do: Citations.relearn()

        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error,
         Error.caught(:seshat_dispatch_failed, :seshat_user_kinds_dispatch_failed, reason)}
    end
  end
end
