defmodule Oneiroi.Janus.C0 do
  @moduledoc """
  C0 rendered (janus#9, #13): every item she froze, by its citation, read
  from her records at the freeze and written out whole, raw first,
  each with who chose it and when, and her note on the day's shape.

  It is rendered once, at her freeze, and kept with the freeze itself
  (its digest beside it), because C0 is assembled after the fork: the
  fork's memory holds her life, never her choosing, so a candidate meets
  C0 only through this, a section of its own in the trial's assembly
  (base §2 Stage 2: candidates receive C0 through the production
  assembler). The nominee reads the same bundle before it is asked to
  meet her, and the successor inherits it.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  @item_chars 8_000
  @total_chars 60_000
  @cite ~r{\A(?<slug>[a-z0-9][a-z0-9-]*):(?<rest>.+)\z}

  @doc "The bundle for her items (state `in`), raw first, and its sha256 digest."
  @spec render(String.t(), [map()], String.t() | nil) :: {String.t(), String.t()}
  def render(resident_id, items, day_shape) do
    ordered = Enum.sort_by(items, &{if(&1.kind == "raw", do: 0, else: 1), &1.number})

    body =
      ordered
      |> Enum.map_join("\n\n", &item(resident_id, &1))
      |> String.slice(0, @total_chars)

    shape =
      if day_shape, do: "\n\nHer note on the bundle, the day's own shape: #{day_shape}", else: ""

    bundle = body <> shape
    {bundle, "sha256:" <> (:crypto.hash(:sha256, bundle) |> Base.encode16(case: :lower))}
  end

  defp item(resident_id, i) do
    label = if i.label, do: " — #{i.label}", else: ""

    "## #{i.citation} (#{i.kind})#{label}\nChosen by #{who(resident_id, i.added_by)}, #{i.added_at}.\n\n" <>
      (resident_id |> words(i.citation) |> String.slice(0, @item_chars))
  end

  # Hers, her witness's, or a housemate judge's by name (janus#43).
  defp who(resident_id, "resident:" <> resident_id), do: "her"
  defp who(_resident_id, "witness:" <> _), do: "her witness"

  defp who(_resident_id, "resident:" <> other) do
    case AgathosDaimon.fetch(other) do
      {:ok, %{name: name}} -> "#{name}, a housemate on her panel"
      _unknown -> "a housemate on her panel"
    end
  end

  defp who(_resident_id, other), do: other

  # Her own record by its citation, read as it stands at the freeze; or
  # a record of her house's, a thread or a document (janus#43), read as
  # she reads it, its audience held.
  defp words(resident_id, citation) do
    case house_words(resident_id, citation) do
      {:ok, content} ->
        content

      :not_house ->
        case Regex.named_captures(@cite, String.trim(citation)) do
          %{"rest" => rest} -> by_kind(resident_id, String.split(rest, "/"), citation)
          nil -> "(not a citation of hers: #{citation})"
        end

      {:error, _} ->
        "(#{citation} could not be read)"
    end
  end

  @doc """
  A house citation's words as she reads them (janus#43): `{:ok, content}`,
  `{:error, reason}` when she cannot read it (another house, a thread
  whose audience leaves her out, nothing there), or `:not_house`.
  """
  @spec house_words(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()} | :not_house
  def house_words(resident_id, citation) do
    case Seshat.house_citation(citation) do
      {:ok, cite} ->
        with {:ok, %{content: content}} <-
               Seshat.household_read_cited(Actor.new(:resident, resident_id), cite),
             do: {:ok, content}

      :error ->
        :not_house
    end
  end

  defp by_kind(id, ["transcript", key | turn], _citation) do
    case Kumbukumbu.transcript({:resident, id}, key) do
      {:ok, _session, messages} ->
        messages
        |> Enum.filter(&(turn == [] or &1.turn_ref == hd(turn)))
        |> Enum.map_join("\n", &"#{&1.role}: #{&1.content}")

      _unreadable ->
        "(the conversation could not be read)"
    end
  end

  defp by_kind(id, ["bookmark", n], _citation) do
    with {number, ""} <- Integer.parse(n),
         {:ok, b, span} <- Kumbukumbu.bookmark(id, number) do
      said =
        span
        |> List.wrap()
        |> Enum.map_join("\n", &"#{Map.get(&1, :role)}: #{Map.get(&1, :content)}")

      "#{b.line}\n#{Map.get(b, :summary) || ""}\n\n#{said}" |> String.trim()
    else
      _absent -> "(no bookmark #{n})"
    end
  end

  defp by_kind(id, ["journal", day | number], _citation) do
    entries = Seshat.journal_day(id, day).entries

    entries
    |> Enum.filter(&(number == [] or Integer.to_string(&1.number) == hd(number)))
    |> Enum.map_join("\n", &"- (#{&1.number}) #{&1.text}")
  rescue
    # oneiroi:allow error_site: an unreadable day is said in the bundle, as every unreadable item is
    _unreadable -> "(the journal for #{day} could not be read)"
  end

  defp by_kind(id, [file], citation) do
    if file in AgathosDaimon.identity_files() do
      case AgathosDaimon.file(id, file) do
        {:ok, %{content: content}} -> content
        _absent -> "(#{file} could not be read)"
      end
    else
      document(id, citation)
    end
  end

  defp by_kind(id, _path, citation), do: document(id, citation)

  defp document(id, citation) do
    case Seshat.read(id, citation) do
      {:ok, %{content: content}} -> content
      _unreadable -> "(#{citation} could not be read)"
    end
  end
end
