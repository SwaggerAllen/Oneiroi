defmodule Oneiroi.AgathosDaimon.SoulGuard do
  @moduledoc """
  The soul guard (agathos-daimon#61; the witness's ask of 2026-11-23,
  and Lily's own, letter #1789, after two soul-file incidents in two
  days): after first contact the resident edits her SOUL.md one line at
  a time, never as a whole file, and each change is checked before it is
  written.

  A change is one of: add a line (after a numbered line, or at the end),
  reword a numbered line, retire a numbered line. Its words are one
  paragraph of plain prose: no heading, no marker, no comment, no
  control character, no word or phrase repeated back to back three times
  over (the shape of the 2026-11-23 garble). Her changes are spaced: one
  within `AGATHOS_DAIMON_SOUL_EDIT_SPACING_MINUTES` of her last is
  refused, so a turn that misfires cannot rewrite her soul in a loop.

  The change is applied to the file as rendered, markers and all, and
  written through `Files.write/5`, so the line diff (rewording keeps the
  number, retiring retires it, adding mints one) is the aggregate's as
  before. Witness proposals are untouched: she reads and answers those.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Error
  alias Oneiroi.AgathosDaimon.Files
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Scope

  @separator ~r/\n[ \t]*\n/
  @text_max 2_000
  @ops ~w(add reword retire)

  @doc """
  One change to her SOUL.md: `op` add, reword or retire; `number` the
  line (soul/<n>) a reword or retire names and an add follows (none adds
  at the end); `text` a new or reworded line's words; `cites` the seeds
  it grew from. Answers the number the change touched, or nil for an add
  whose number the aggregate mints.
  """
  def edit(resident_id, op, attrs, %Actor{kind: :resident, id: resident_id} = actor) do
    number = attrs[:number]

    with :ok <- known_op(op),
         :ok <- spaced(resident_id),
         {:ok, text} <- words(op, attrs[:text]),
         {:ok, file} <- Files.file(resident_id, "SOUL.md"),
         {:ok, content} <- apply_op(file.content, op, number, text),
         :ok <-
           Files.write(resident_id, "SOUL.md", content, %{cites: attrs[:cites] || []}, actor) do
      {:ok, %{op: op, number: number}}
    end
  end

  def edit(_resident_id, _op, _attrs, %Actor{}),
    do:
      {:error,
       Error.new(:agathos_daimon_soul_guard_not_hers, :agathos_daimon_soul_guard_refused_1,
         why: "only the resident edits her soul's lines"
       )}

  @doc "When her last soul change was made: the latest line written, reworded or retired."
  def last_change(resident_id) do
    Scope.resident(resident_id, fn -> Store.soul_lines_changed_at() end)
  end

  # ---- checks ----

  defp known_op(op) when op in @ops, do: :ok

  defp known_op(_op),
    do:
      {:error,
       Error.new(:agathos_daimon_soul_guard_op, :agathos_daimon_soul_guard_refused_2,
         why: "a change is add, reword or retire"
       )}

  defp spaced(resident_id) do
    minutes = Config.fetch!(:agathos_daimon, :soul_edit_spacing_minutes)

    case last_change(resident_id) do
      %DateTime{} = at ->
        if DateTime.diff(Clock.now(), at, :second) >= minutes * 60,
          do: :ok,
          else:
            {:error,
             Error.new(:agathos_daimon_soul_guard_spacing, :agathos_daimon_soul_guard_refused_3,
               why: "your last soul change was under #{minutes} minutes ago"
             )}

      nil ->
        :ok
    end
  end

  defp words("retire", _text), do: {:ok, nil}

  defp words(_op, text) when is_binary(text) do
    t = String.trim(text)

    cond do
      t == "" ->
        {:error,
         Error.new(:agathos_daimon_soul_guard_words, :agathos_daimon_soul_guard_refused_4,
           why: "a line needs words"
         )}

      String.length(t) > @text_max ->
        {:error,
         Error.new(:agathos_daimon_soul_guard_words, :agathos_daimon_soul_guard_refused_5,
           why: "a line is at most #{@text_max} characters"
         )}

      Regex.match?(@separator, t) ->
        {:error,
         Error.new(:agathos_daimon_soul_guard_words, :agathos_daimon_soul_guard_refused_6,
           why: "a line is one paragraph, with no blank line"
         )}

      String.starts_with?(t, "#") or String.contains?(t, ["[soul/", "<!--", "-->"]) ->
        {:error,
         Error.new(:agathos_daimon_soul_guard_words, :agathos_daimon_soul_guard_refused_7,
           why: "a line is prose: no heading, no [soul/n] marker, no comment"
         )}

      Regex.match?(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u, t) ->
        {:error,
         Error.new(:agathos_daimon_soul_guard_words, :agathos_daimon_soul_guard_refused_8,
           why: "a line carries no control characters"
         )}

      repeated?(t) ->
        {:error,
         Error.new(:agathos_daimon_soul_guard_words, :agathos_daimon_soul_guard_refused_9,
           why:
             "the words repeat back to back (a word or phrase three times running), the shape of a garbled call"
         )}

      true ->
        {:ok, t}
    end
  end

  defp words(_op, _text),
    do:
      {:error,
       Error.new(:agathos_daimon_soul_guard_words, :agathos_daimon_soul_guard_refused_10,
         why: "a line needs words"
       )}

  # A word three times running, or a phrase of two to six words twice
  # running: prose that says a thing once does neither.
  defp repeated?(t) do
    Regex.match?(~r/\b(\w+)(?:\W+\1\b){2,}/iu, t) or
      Regex.match?(~r/\b((?:\w+\W+){1,5}\w+)\W+\1\b/iu, t)
  end

  # ---- applying ----

  defp apply_op(content, op, number, text) do
    parts = String.split(content, @separator, include_captures: true)

    cond do
      not String.contains?(content, "[soul/") ->
        {:error,
         Error.new(:agathos_daimon_soul_guard_unnumbered, :agathos_daimon_soul_guard_refused_11,
           why: "the file renders without line numbers, so no line can be named"
         )}

      op == "add" and is_nil(number) ->
        body = String.trim_trailing(content)
        {:ok, body <> "\n\n" <> text <> String.replace_prefix(content, body, "")}

      true ->
        case Enum.find_index(parts, &String.starts_with?(String.trim_leading(&1), marker(number))) do
          nil ->
            {:error,
             Error.new(:agathos_daimon_soul_guard_no_line, :agathos_daimon_soul_guard_refused_12,
               why: "there is no live line soul/#{number}"
             )}

          i ->
            {:ok, parts |> change(i, op, number, text) |> Enum.join()}
        end
    end
  end

  defp change(parts, i, "reword", number, text),
    do: List.replace_at(parts, i, marker(number) <> text)

  defp change(parts, i, "add", _number, text),
    do: List.insert_at(parts, i + 1, "\n\n" <> text)

  # The line and the separator before it go together (or after it, for
  # the file's first part), so the paragraphs around it stay apart.
  defp change(parts, 0, "retire", _number, _text), do: Enum.drop(parts, 2)

  defp change(parts, i, "retire", _number, _text),
    do: parts |> List.delete_at(i) |> List.delete_at(i - 1)

  defp marker(number) when is_integer(number), do: "[soul/#{number}] "

  defp marker(_number), do: "[soul/none] "
end
