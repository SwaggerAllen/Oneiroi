defmodule Oneiroi.AgathosDaimon.Files do
  @moduledoc """
  The identity files (spec §6.2, F2): the command edge for writing a seed
  or an edit, proposing one after first contact and deciding a proposal;
  the reads the brain's prefix and the Files screen take; and the
  build-owned `AGENTS.md`, rendered from a template by name and slug and
  never written.

  Before first contact the files are given: a witness writes with the
  seed's origin. After it a witness's write is refused in favour of a
  proposal, which the resident accepts in its own actor or declines, each
  with a note. The resident's own edit applies at any time.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Error
  alias Oneiroi.AgathosDaimon.Resident
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.AgathosDaimon.SoulLines
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Scope

  @instructions_template "templates/honcho-custom-instructions.md"
  @agents_template "templates/AGENTS.md"

  @doc "Writes a file: a seed with `origin` (and `model`, `prompt` when drafted) before first contact, the resident's edit after; `cites` the seeds its new soul lines grew from."
  @spec write(String.t(), String.t(), String.t(), map(), Actor.t()) :: :ok | {:error, term()}
  def write(resident_id, file, content, attrs, %Actor{} = actor) when is_map(attrs) do
    command = %Commands.WriteFile{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      file: file,
      content: content,
      origin: Map.get(attrs, :origin, "authored"),
      model: Map.get(attrs, :model),
      prompt: Map.get(attrs, :prompt),
      cites: Map.get(attrs, :cites, [])
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  @doc "A witness proposes an edit after first contact, with a note; returns the proposal's ref."
  def propose(resident_id, file, content, note, %Actor{} = actor) do
    ref = 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    command = %Commands.ProposeSoulEdit{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      ref: ref,
      file: file,
      content: content
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: {:ok, ref}
  end

  @doc "The resident accepts a proposal, applying it, with a note and the seeds its new soul lines cite."
  def accept(resident_id, ref, note, cites, %Actor{kind: :resident} = actor) do
    command = %Commands.AcceptSoulEdit{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      ref: ref,
      cites: cites
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  def accept(_resident_id, _ref, _note, _cites, %Actor{}),
    do:
      {:error,
       Error.new(:agathos_daimon_not_the_resident, :agathos_daimon_files_accept_not_resident)}

  @doc "The resident declines a proposal, with a note."
  def decline(resident_id, ref, note, %Actor{kind: :resident} = actor) do
    command = %Commands.DeclineSoulEdit{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      ref: ref
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  def decline(_resident_id, _ref, _note, %Actor{}),
    do:
      {:error,
       Error.new(:agathos_daimon_not_the_resident, :agathos_daimon_files_decline_not_resident)}

  @doc "Records first contact: the first captured turn outside a regression session. Idempotent."
  def first_contact(resident_id, session_key, turn_ref, %Actor{} = actor) do
    command = %Commands.RecordFirstContact{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      session_key: session_key,
      turn_ref: turn_ref
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  # ---- reads ----

  @doc "The resident's identity files as rows, by name, the soul rendered with its line markers."
  def files(resident_id) do
    Scope.resident(resident_id, fn -> Enum.map(Store.files(), &rendered/1) end)
  end

  @doc "The soul file's live lines in the file's order (spec §6.17, P39)."
  @spec soul_lines(String.t()) :: [Store.SoulLine.t()]
  def soul_lines(resident_id), do: Scope.resident(resident_id, fn -> Store.soul_lines() end)

  @doc """
  The stable prefix (spec §5): the identity files written so far in a
  fixed order, then the build-owned `AGENTS.md`, as `{name, content}`
  pairs, so a cached prefix is the same from turn to turn until a file
  changes. The brain's context and the sealed regression session both
  read this and nothing else of the resident's files.
  """
  @spec context(String.t()) :: [{String.t(), String.t()}]
  def context(resident_id) do
    read = fn -> {Store.get(resident_id), Enum.map(Store.files(), &rendered/1)} end

    case Scope.resident(resident_id, read) do
      {nil, _files} ->
        []

      {row, files} ->
        written = Map.new(files, &{&1.name, &1.content})

        ordered =
          for name <- Resident.files(), content = Map.get(written, name), do: {name, content}

        ordered ++ [{"AGENTS.md", agents_md(row)}]
    end
  end

  @doc """
  The build-owned `honcho/custom-instructions.md` for a resident, from
  `priv/templates/honcho-custom-instructions.md` with the name and the
  two peer names filled in: rendered rather than stored, like `AGENTS.md`.
  """
  @spec custom_instructions(map()) :: String.t()
  # The template is a file this repository ships, named by code.
  # sobelow_skip ["Traversal.FileModule"]
  def custom_instructions(%{id: id, name: name, account_id: account_id}) do
    :oneiroi
    |> :code.priv_dir()
    |> Path.join(@instructions_template)
    |> File.read!()
    |> String.replace("{{name}}", name)
    |> String.replace("{{resident_peer}}", "resident-" <> id)
    |> String.replace("{{witness_peer}}", "witness-" <> account_id)
  end

  @doc "One file's row, or the rendered `AGENTS.md`."
  def file(resident_id, "AGENTS.md") do
    case Scope.resident(resident_id, fn -> Store.get(resident_id) end) do
      nil ->
        {:error,
         Error.new(:agathos_daimon_no_such_file, :agathos_daimon_files_agents_md_absent,
           file: "AGENTS.md"
         )}

      row ->
        {:ok, %{name: "AGENTS.md", content: agents_md(row), origin: "build", version: 0}}
    end
  end

  def file(resident_id, name) do
    case Scope.resident(resident_id, fn -> Store.file(name) end) do
      nil ->
        {:error,
         Error.new(:agathos_daimon_no_such_file, :agathos_daimon_files_file_absent, file: name)}

      row ->
        {:ok, Scope.resident(resident_id, fn -> rendered(row) end)}
    end
  end

  # The soul is read with its markers so a line can be cited by what the
  # reader sees (`<slug>:soul/<n>`) and an edit of the rendered file
  # keeps every line's number; the row keeps the words alone. Under the
  # caller's resident scope already.
  defp rendered(%{name: "SOUL.md"} = row),
    do: %{row | content: SoulLines.render(row.content, Store.soul_lines())}

  defp rendered(row), do: row

  @doc "The open soul-edit proposals, oldest first."
  def proposals(resident_id), do: Scope.resident(resident_id, fn -> Store.open_soul_edits() end)

  @doc """
  The build-owned `AGENTS.md` for a resident, from `priv/templates/AGENTS.md`
  with the name and slug filled in: read-only in the client, rendered
  rather than stored so a template change reaches every resident.
  """
  @spec agents_md(map()) :: String.t()
  # The template is a file this repository ships, named by code.
  # sobelow_skip ["Traversal.FileModule"]
  def agents_md(%{name: name, slug: slug}) do
    :oneiroi
    |> :code.priv_dir()
    |> Path.join(@agents_template)
    |> File.read!()
    |> String.replace("{{name}}", name)
    |> String.replace("{{slug}}", slug)
  end
end
