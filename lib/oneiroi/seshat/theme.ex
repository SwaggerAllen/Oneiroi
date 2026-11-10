defmodule Oneiroi.Seshat.Theme do
  @moduledoc """
  Her theme (seshat#56): three seeds, a ground, her colour and her
  witness's, from which the client derives every colour on the screen.
  The seeds are the witness's (the witness, 2026-11-10); she changes them
  by proposal only.

  Repo first: the seeds are `THEME.md` at the root of her repository,
  frontmatter a person can read with a note under it, so the theme
  travels with her export. The file is the truth and is read from disk;
  until it exists, or when it does not carry three `#rrggbb` seeds, the
  decided look's seeds stand. It is a root document, written only
  through here: a document write of it, from either party, is refused
  (`Documents`), so every set it holds passed the readability checks.

  The checks are the client's (`Palette`, ported; the fixture keeps the
  two agreeing). The witness's set is refused when they fail; her
  proposal is refused to her with the report in words, and filed only
  when they pass. A filed proposal waits on his list (brain#80); his
  answer is a letter to her chat, the way a plugin proposal's answer
  reaches her (brain#68), and accepted, the file is written.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Leases
  alias Oneiroi.Seshat.Palette
  alias Oneiroi.Seshat.Store
  alias Oneiroi.Seshat.ThemeRouter
  alias Oneiroi.SimaQian

  @file_name "THEME.md"
  @roles [:ground, :resident, :witness]

  @doc "The theme's file, at her repository's root."
  @spec file_name() :: String.t()
  def file_name, do: @file_name

  @doc """
  The theme as both parties read it: the seeds (`source: "file"` or
  `"default"`), the checks on them and whether they passed, and the
  proposals, newest first.
  """
  def read(resident_id) do
    {seeds, source} =
      case seeds_on_disk(resident_id) do
        {:ok, seeds} -> {seeds, "file"}
        :none -> {Palette.default(), "default"}
      end

    %{checks: checks, ok: ok} = Palette.derive(seeds)

    %{
      file: @file_name,
      seeds: seeds,
      source: source,
      ok: ok,
      checks: checks,
      proposals: proposals(resident_id)
    }
  end

  @doc "Her proposals, newest first, each with his answer once given."
  def proposals(resident_id) do
    for p <- Scope.resident(resident_id, fn -> Store.theme_proposals() end),
        do: %{
          number: p.number,
          seeds: %{ground: p.ground, resident: p.resident, witness: p.witness},
          note: p.note,
          proposed_at: p.proposed_at,
          agree: p.agree,
          answered_by: p.answered_by,
          answer_note: p.answer_note,
          answered_at: p.answered_at
        }
  end

  @doc "The witness sets the seeds: checked, then written as THEME.md with his note."
  def set(resident_id, attrs, note, %Actor{kind: :witness} = actor) do
    with {:ok, seeds} <- seeds(attrs),
         :ok <- readable(seeds),
         :ok <- write(resident_id, seeds, said(actor, note), note, actor) do
      {:ok, read(resident_id)}
    end
  end

  def set(_resident_id, _attrs, _note, _actor),
    do: {:error, Error.new(:seshat_theme_not_his, :seshat_theme_set_not_his)}

  @doc """
  She proposes seeds: checked first, and refused with the report when
  they fail; filed, they wait on her witness. `{:ok, number, derived}`.
  """
  def propose(resident_id, attrs, note, %Actor{} = actor) do
    with {:ok, seeds} <- seeds(attrs),
         :ok <- noted(note),
         :ok <- readable(seeds),
         {:ok, [%{number: n}]} <-
           dispatch(%Commands.ProposeTheme{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             ground: seeds.ground,
             resident: seeds.resident,
             witness: seeds.witness,
             note: note
           }) do
      {:ok, n, Palette.derive(seeds)}
    end
  end

  @doc "The witness accepts or declines her proposal, with a note; accepted, THEME.md is written. She is told by a letter to her chat."
  def answer(resident_id, number, agree, note, %Actor{} = actor) do
    with :ok <- noted(note),
         {:ok, p} <- proposal(resident_id, number),
         {:ok, _} <-
           dispatch(%Commands.AnswerTheme{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             number: number,
             agree: agree == true,
             note: note
           }),
         :ok <- if(agree == true, do: accepted(resident_id, p, note, actor), else: :ok) do
      tell(resident_id, number, agree == true, note, actor)
    end
  end

  defp accepted(resident_id, p, note, actor) do
    seeds = %{ground: p.ground, resident: p.resident, witness: p.witness}

    said =
      "Proposed by the resident as ##{p.number}: #{p.note}\n\nAccepted by the witness, #{today()}: #{note}"

    write(resident_id, seeds, said, "accepted theme proposal ##{p.number}: #{note}", actor)
  end

  defp tell(resident_id, number, agree, note, %Actor{kind: :witness} = witness) do
    what =
      if agree,
        do: "accepted your theme proposal ##{number}; THEME.md now holds your seeds: #{note}",
        else: "declined your theme proposal ##{number}; the theme stays as it was: #{note}"

    _ =
      Kumbukumbu.send_letter(
        resident_id,
        nil,
        %{to: "Oneiroi chat", text: "Your witness " <> what},
        witness
      )

    :ok
  end

  defp tell(_resident_id, _number, _agree, _note, _actor), do: :ok

  defp proposal(resident_id, number) do
    case Enum.find(
           Scope.resident(resident_id, fn -> Store.theme_proposals() end),
           &(&1.number == number)
         ) do
      nil -> {:error, Error.new(:seshat_theme_answer_invalid, :seshat_theme_no_such_proposal)}
      p -> {:ok, p}
    end
  end

  # ---- the seeds ----

  @doc "Three `#rrggbb` seeds from a map with string or atom keys, lower-cased."
  def seeds(attrs) when is_map(attrs) do
    seeds = Map.new(@roles, &{&1, value(attrs, &1)})

    if Enum.all?(seeds, fn {_role, v} -> Palette.hex?(v) end),
      do: {:ok, Map.new(seeds, fn {role, v} -> {role, String.downcase(v)} end)},
      else: {:error, Error.new(:seshat_theme_invalid, :seshat_theme_seeds_not_hex)}
  end

  def seeds(_other), do: {:error, Error.new(:seshat_theme_invalid, :seshat_theme_seeds_not_a_map)}

  defp value(attrs, role) do
    case Map.get(attrs, role, Map.get(attrs, Atom.to_string(role))) do
      v when is_binary(v) -> String.trim(v)
      other -> other
    end
  end

  defp readable(seeds) do
    %{ok: ok, checks: checks} = Palette.derive(seeds)

    if ok,
      do: :ok,
      else:
        {:error,
         Error.new(:seshat_theme_unreadable, :seshat_theme_checks_failed,
           checks: checks,
           failed: for(c <- checks, not c.passed, do: c.name)
         )}
  end

  defp noted(note) do
    if is_binary(note) and String.trim(note) != "",
      do: :ok,
      else: {:error, Error.new(:seshat_theme_invalid, :seshat_theme_no_note)}
  end

  # ---- the file ----

  @doc "Renders THEME.md: the seeds as frontmatter, what they are, and what was said of this set."
  def render(seeds, said) do
    """
    ---
    ground: "#{seeds.ground}"
    resident: "#{seeds.resident}"
    witness: "#{seeds.witness}"
    ---

    # Theme

    The three seeds the screen is coloured from (seshat#56): the ground,
    her colour and her witness's. Every other colour is derived from them,
    and a set that would make the screen hard to read is refused. Her
    witness sets them; she proposes a change with theme_propose.

    #{said}
    """
  end

  @doc "Reads the seeds out of THEME.md's frontmatter; `:none` unless all three are there."
  def parse(content) when is_binary(content) do
    with [_, front] <- Regex.run(~r/\A---\s*\n(.*?)\n---\s*(?:\n|\z)/s, content),
         found =
           for(
             [_, role, hex] <-
               Regex.scan(
                 ~r/^\s*(ground|resident|witness)\s*:\s*["']?(#[0-9a-fA-F]{6})["']?\s*$/m,
                 front
               ),
             into: %{},
             do: {String.to_existing_atom(role), String.downcase(hex)}
           ),
         3 <- map_size(found) do
      {:ok, found}
    else
      _ -> :none
    end
  end

  # The name is this module's constant, never a caller's.
  # sobelow_skip ["Traversal.FileModule"]
  defp seeds_on_disk(resident_id) do
    with {:ok, dir} <- SimaQian.repository_dir(resident_id),
         {:ok, content} <- File.read(Path.join(dir, @file_name)) do
      parse(content)
    else
      _absent -> :none
    end
  end

  defp write(resident_id, seeds, said, note, actor) do
    case Leases.write(resident_id, @file_name, render(seeds, said), actor,
           note: note,
           theme: true
         ) do
      {:ok, _} -> :ok
      {:error, _} = failed -> failed
    end
  end

  defp said(_actor, note) when is_binary(note) and note != "",
    do: "Set by the witness, #{today()}: #{note}"

  defp said(_actor, _note), do: "Set by the witness, #{today()}."

  defp today, do: Clock.now() |> DateTime.to_date() |> Date.to_iso8601()

  defp dispatch(command) do
    case ThemeRouter.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:seshat_dispatch_failed, :seshat_theme_dispatch_failed, reason)}
    end
  end
end
