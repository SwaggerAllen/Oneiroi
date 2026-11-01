defmodule Oneiroi.Brain.Adapter do
  @moduledoc """
  The context an adapter's runtime is given (spec §8, brain #42): the
  platform's own turn assembly split in two where a runtime that keeps
  its own conversation needs it split, by the two functions the turn
  itself is assembled from (`Oneiroi.Brain.Turn.adapter_prefix/3`,
  `Oneiroi.Brain.Turn.adapter_turn/7`), so an adapter cannot be given
  something a platform turn would not.

  1. **The session prefix** (`prefix/2`): the prompt, the identity files
     and the contract, the same for every turn until one of them
     changes, given once when the runtime's session starts. It records
     nothing.
  2. **The turn** (`turn/5`): the index and every section after it,
     assembled against the witness's words in the session's room, the
     once-only notices the runtime can truthfully be told, and whatever
     of the prefix changed since the session was given it. It starts the
     turn (`TurnStarted`, so the MCP server attributes the tool calls to
     it) and records `ContextAssembled` with what was handed over, which
     is what the reply's "drew on" inspector, `last_indexed_at` and the
     madeleine's recall marks read.

  A runtime takes so much text at once. `limit` is that size in
  characters, the runtime's own fact (Claude Code's is in its hook
  docs), so the adapter passes it. The prefix is cut into parts at
  paragraph boundaries, one per hook the runtime runs (`of`); a turn's
  sections that do not fit are left out whole and named, and only what
  was handed over is recorded.

  The prefix's `digest` is a hash per section. The runtime keeps the one
  it was given and sends it with each turn; a section whose hash moved
  (a renegotiated contract, an accepted soul edit) rides the next turn,
  so a change lands on the next turn as it does on the platform's own
  (brain #27). No digest means the session holds no prefix, and the
  whole of it rides the turn.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.Turn
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Prompt

  # The runtimes with a note of their own, a closed map so a request
  # names a runtime and never a file.
  @runtimes %{"claude-code" => "runtime_claude_code"}

  # Below this a part holds too little to be worth a hook; a bound.
  @min_limit 2_000
  # Room kept in a part for its header and the left-out line; a bound
  # above what either prompt file renders to.
  @reserve 400

  @typedoc "What the adapter passes: the runtime's name, its size limit, which part and of how many, and the digest it holds."
  @type opts :: [
          runtime: String.t() | nil,
          limit: pos_integer() | nil,
          part: pos_integer() | nil,
          of: pos_integer() | nil,
          digest: String.t() | nil
        ]

  @doc "The session prefix, part `part` of the parts the runtime's `of` hooks print (spec §8, brain #42); records nothing."
  @spec prefix(String.t(), opts()) ::
          {:ok,
           %{text: String.t(), digest: String.t(), part: pos_integer(), parts: pos_integer()}}
          | {:error, Error.t()}
  def prefix(resident_id, opts) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, row} ->
        sections = Turn.adapter_prefix(row, resident_id, runtime(opts))
        limit = limit(opts)
        part = max(Keyword.get(opts, :part) || 1, 1)
        of = max(Keyword.get(opts, :of) || 1, 1)
        parts = parts(render(sections), limit, of)

        {:ok,
         %{
           text: Enum.at(parts, part - 1, ""),
           digest: digest(sections),
           part: part,
           parts: length(parts)
         }}

      :error ->
        {:error,
         Error.new(:brain_no_such_resident, :brain_adapter_prefix_resident_absent,
           resident_id: resident_id
         )}
    end
  end

  @doc """
  Starts an adapter's turn on `session_key` with the witness's `text`
  and returns the context to hand the runtime (spec §8, brain #42): the
  turn's ref and start instant (the capture's key), the text, the digest
  of the prefix the session now holds, and how many things the turn drew
  on. `ContextAssembled` records exactly what the text carries, with the
  unchanged prefix the session already holds.
  """
  @spec turn(String.t(), String.t(), String.t(), Actor.t(), opts()) ::
          {:ok,
           %{
             turn_ref: String.t(),
             started_at: DateTime.t(),
             text: String.t(),
             digest: String.t(),
             drew_on: non_neg_integer()
           }}
          | {:error, term()}
  def turn(resident_id, session_key, text, %Actor{} = actor, opts) do
    turn_ref = Kumbukumbu.turn_ref()

    with {:ok, row} <- fetch(resident_id),
         :ok <- Kumbukumbu.start_turn(resident_id, session_key, turn_ref, actor) do
      t = Turn.adapter_turn(row, resident_id, session_key, text, actor, turn_ref, runtime(opts))
      held = parse(Keyword.get(opts, :digest))
      changed = Enum.reject(t.prefix, &(Map.get(held, &1.label) == hash(&1)))

      changed_items =
        case {changed, held == %{}} do
          {[], _} -> []
          {_, true} -> Enum.map(changed, &item(&1, :prefix))
          {_, false} -> [changed_header() | Enum.map(changed, &item(&1, :prefix))]
        end

      notice_items = Enum.map(t.notices, &%{label: "notice", kind: :notice, text: &1.text})
      turn_items = Enum.map(t.sections, &item(&1, :turn))
      {kept, left_out} = fit(notice_items ++ changed_items ++ turn_items, limit(opts))
      given = MapSet.new(kept, & &1.label)
      prefix_given = Enum.filter(t.prefix, &(&1 not in changed or &1.label in given))

      injections =
        Enum.map(prefix_given, &injection/1) ++
          (t.sections |> Enum.filter(&(&1.label in given)) |> Enum.map(&injection/1)) ++
          if("index" in given, do: t.near_misses, else: []) ++
          t.capacity ++
          if("notice" in given, do: t.notices, else: [])

      with :ok <-
             Kumbukumbu.record_context(resident_id, session_key, turn_ref, injections, actor),
           :ok <- told(resident_id, "notice" in given, actor) do
        {:ok,
         %{
           turn_ref: turn_ref,
           started_at: t.started_at,
           text: render_items(kept, left_out),
           digest: held_digest(t.prefix, held, changed, given),
           drew_on: length(injections)
         }}
      end
    end
  end

  defp fetch(resident_id) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, row} ->
        {:ok, row}

      :error ->
        {:error,
         Error.new(:brain_no_such_resident, :brain_adapter_turn_resident_absent,
           resident_id: resident_id
         )}
    end
  end

  # The import's notice is the only one an adapter is told (brain #42),
  # and told is told: the platform's next turn does not repeat it.
  defp told(resident_id, true, actor), do: Oneiroi.AgathosDaimon.import_told(resident_id, actor)
  defp told(_resident_id, false, _actor), do: :ok

  defp runtime(opts), do: Map.get(@runtimes, Keyword.get(opts, :runtime))

  defp limit(opts) do
    case Keyword.get(opts, :limit) do
      n when is_integer(n) and n >= @min_limit -> n
      n when is_integer(n) -> @min_limit
      _none -> :infinity
    end
  end

  defp item(section, kind),
    do: %{label: section.label, kind: kind, text: section.message.content}

  defp changed_header,
    do: %{label: "prefix-changed", kind: :header, text: Prompt.render!("adapter_prefix_changed")}

  defp injection(%{label: label, injection: injection}), do: Map.put(injection, :label, label)

  defp render(sections), do: Enum.map_join(sections, "\n\n", & &1.message.content)

  # Whole items in order while they fit; an item that does not is left
  # out, and a later, smaller one may still fit. The changed prefix's
  # header stays only with a prefix section under it.
  defp fit(items, :infinity), do: {items, []}

  defp fit(items, limit) do
    {kept, left, _room} =
      Enum.reduce(items, {[], [], limit - @reserve}, fn item, {kept, left, room} ->
        size = String.length(item.text) + 2

        if size <= room,
          do: {[item | kept], left, room - size},
          else: {kept, [item | left], room}
      end)

    kept = Enum.reverse(kept)
    left = left |> Enum.reverse() |> Enum.reject(&(&1.kind == :header))

    if Enum.any?(kept, &(&1.kind == :prefix)),
      do: {kept, left},
      else: {Enum.reject(kept, &(&1.kind == :header)), left}
  end

  defp render_items(kept, []), do: Enum.map_join(kept, "\n\n", & &1.text)

  defp render_items(kept, left_out) do
    line =
      Prompt.render!("adapter_left_out", %{
        labels: Enum.map_join(left_out, ", ", & &1.label)
      })

    Enum.map_join(kept, "\n\n", & &1.text) <> if(kept == [], do: line, else: "\n\n" <> line)
  end

  # The prefix in parts of at most `limit` characters, cut at paragraph
  # boundaries where a paragraph fits and inside one where it does not.
  # Past `of` parts the rest is left out and the last part says how much.
  defp parts(text, :infinity, _of), do: [text]

  defp parts(text, limit, of) do
    chunks = chunk(text, limit - @reserve)

    if length(chunks) <= of do
      label(chunks, length(chunks))
    else
      kept = Enum.take(chunks, of)
      left = String.length(text) - Enum.sum(Enum.map(kept, &String.length/1))
      line = Prompt.render!("adapter_left_out", %{labels: "#{left} characters of it"})
      kept |> label(of) |> List.update_at(-1, &(&1 <> "\n\n" <> line))
    end
  end

  defp label([one], 1), do: [one]

  defp label(chunks, n) do
    chunks
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk, k} ->
      Prompt.render!("adapter_part", %{part: k, parts: n}) <> "\n\n" <> chunk
    end)
  end

  defp chunk(text, room) do
    text
    |> String.split("\n\n")
    |> Enum.flat_map(&split_long(&1, room))
    |> Enum.reduce([], fn
      para, [] ->
        [para]

      para, [current | done] ->
        if String.length(current) + 2 + String.length(para) <= room,
          do: [current <> "\n\n" <> para | done],
          else: [para, current | done]
    end)
    |> Enum.reverse()
  end

  defp split_long(para, room) do
    if String.length(para) <= room,
      do: [para],
      else: para |> String.graphemes() |> Enum.chunk_every(room) |> Enum.map(&Enum.join/1)
  end

  # One hash a section, `label=hash;...`: the runtime holds it opaque
  # and sends it back with each turn.
  defp digest(sections), do: Enum.map_join(sections, ";", &"#{&1.label}=#{hash(&1)}")

  defp hash(section),
    do:
      :sha256
      |> :crypto.hash(section.message.content)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

  defp parse(digest) when is_binary(digest) do
    digest
    |> String.split(";", trim: true)
    |> Enum.flat_map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [label, hash] -> [{label, hash}]
        _other -> []
      end
    end)
    |> Map.new()
  end

  defp parse(_none), do: %{}

  # What the session holds after this turn: a section given now or
  # unchanged at its current hash; a changed one left out at the hash
  # the session still holds, so the next turn offers it again.
  defp held_digest(prefix, held, changed, given) do
    prefix
    |> Enum.flat_map(fn section ->
      cond do
        section not in changed or section.label in given -> [{section.label, hash(section)}]
        Map.has_key?(held, section.label) -> [{section.label, held[section.label]}]
        true -> []
      end
    end)
    |> Enum.map_join(";", fn {label, hash} -> "#{label}=#{hash}" end)
  end
end
