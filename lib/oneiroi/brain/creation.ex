defmodule Oneiroi.Brain.Creation do
  @moduledoc """
  The creation flow's two model calls beyond "Write it with me"
  (`Oneiroi.Brain.Drafting`), both under the `drafting` purpose and both
  from the gifts' own guidance (agathos-daimon#36):

  - **The generator** (agathos-daimon#39): one prompt from the witness,
    who he wants to wake, and back a draft of every gift's file, each
    drafted from its gift's guidance, one call a file in the gifts'
    order, each shown the drafts before it. Returned, never written: the
    witness keeps each through the ordinary write with origin `drafted`,
    the model and the prompt.
  - **Get a read** (agathos-daimon#40): one gift's draft against that
    gift's guidance, back as notes typed `strong`, `thin`, `missing`,
    `question` or `cut` (a part that changes nothing about how they will
    act). Notes only; the draft is never rewritten. The read is recorded
    on the resident's stream beside the seeds, by the draft's hash.

  Lives in the brain for the reason drafting does (brain#14): the ledger
  reaches the resident system for the witness's key, and a system cannot
  depend on one that depends on it.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Error
  alias Oneiroi.Config
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Nisaba.Provider.{Request, Result}

  @type draft :: %{
          gift: String.t(),
          file: String.t(),
          content: String.t(),
          origin: String.t(),
          model: String.t(),
          prompt: String.t()
        }

  @type note :: %{kind: String.t(), text: String.t(), quote: String.t() | nil}

  # The prompt path drafts only the resident's own files: USER.md, GOALS.md
  # and LINKS.md are about the witness, and a prompt about who to wake
  # cannot know them (the witness, 2026-11-10; agathos-daimon#42). Those
  # stay gift by gift, with Write it with me.
  @resident_files ~w(IDENTITY.md SOUL.md)

  @doc "The resident's own files, in the gifts' order: what the generator drafts."
  @spec prompt_files() :: [String.t()]
  def prompt_files, do: Enum.filter(files(), &(&1 in @resident_files))

  @doc "The identity files the gifts write, in the gifts' order."
  @spec files() :: [String.t()]
  def files do
    identity = Oneiroi.AgathosDaimon.identity_files()

    for gift <- Oneiroi.AgathosDaimon.gifts(), file <- gift.writes, file in identity, do: file
  end

  @doc """
  Drafts every gift's file from the witness's `prompt`, in the gifts'
  order, one call each. A call that fails stops the run there: the drafts
  made so far come back with `stopped` naming the file and the failure,
  since each was paid for and is the witness's to keep or not.
  """
  @spec generate(String.t(), String.t(), Actor.t()) ::
          {:ok, %{prompt: String.t(), drafts: [draft()], stopped: map() | nil}}
          | {:error, term()}
  def generate(resident_id, prompt, %Actor{} = actor) when is_binary(prompt) do
    with {:ok, row} <- fetch(resident_id),
         :ok <- in_creation(row) do
      kept = Map.new(Oneiroi.AgathosDaimon.files(resident_id), &{&1.name, &1.content})
      model = Config.fetch!(:brain, :draft_model)

      ask = %{
        resident_id: resident_id,
        name: row.name,
        prompt: prompt,
        model: model,
        actor: actor
      }

      {drafts, stopped} =
        Enum.reduce_while(prompt_files(), {[], nil}, fn file, {drafts, nil} ->
          step(draft_one(ask, file, existing(kept, drafts)), file, drafts)
        end)

      {:ok, %{prompt: prompt, drafts: drafts, stopped: stopped}}
    end
  end

  defp step({:ok, draft}, _file, drafts), do: {:cont, {drafts ++ [draft], nil}}
  defp step({:error, reason}, file, drafts), do: {:halt, {drafts, stopped(file, reason)}}

  defp draft_one(%{name: name, prompt: prompt, model: model} = ask, file, existing) do
    gift = Oneiroi.AgathosDaimon.gift_for(file)

    system =
      Prompt.message("creation_draft", %{
        name: name,
        file: file,
        gift: gift.title,
        guidance: gift.guidance,
        existing: existing
      })

    request = Request.new(model, [system, %{role: :user, content: prompt}])

    case Nisaba.call(ask.resident_id, :drafting, request, ask.actor) do
      {:ok, %Result{content: content} = result} ->
        {:ok,
         %{
           gift: gift.key,
           file: file,
           content: unfenced(content || ""),
           origin: "drafted",
           model: result.model || model,
           prompt: prompt
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A model sometimes wraps the whole file in a code fence; the file is
  # what is inside it. A fence that is part of the file is left alone.
  @doc false
  @spec unfenced(String.t()) :: String.t()
  def unfenced(text) do
    case Regex.run(~r/\A\s*```[a-zA-Z]*\n(.*?)\n```\s*\z/s, text) do
      [_, inner] -> inner
      _ -> text
    end
  end

  # What the model is shown as written so far: this run's drafts, and the
  # kept files it has not drafted yet, so the files read as one person.
  defp existing(kept, drafts) do
    drafted = Map.new(drafts, &{&1.file, &1.content})
    shown = Map.merge(kept, drafted)

    case Enum.filter(files(), &Map.has_key?(shown, &1)) do
      [] -> "Nothing yet."
      names -> Enum.map_join(names, "\n\n", &"## #{&1}\n\n#{shown[&1]}")
    end
  end

  defp stopped(file, %{kind: kind} = reason),
    do: %{file: file, kind: kind, message: Map.get(reason, :message) || to_string(kind)}

  defp stopped(file, reason), do: %{file: file, kind: :failed, message: inspect(reason)}

  @doc """
  Suggests a few trials (agathos-daimon#42) from the resident's files
  written so far and the witness's `note`, under drafting, on the
  drafting model. Returned, never kept: each is kept through the ordinary
  regression write when the witness keeps it.
  """
  @spec suggest_trials(String.t(), String.t(), Actor.t()) ::
          {:ok, %{trials: [map()], model: String.t()}} | {:error, term()}
  def suggest_trials(resident_id, note, %Actor{} = actor) when is_binary(note) do
    with {:ok, row} <- fetch(resident_id),
         :ok <- in_creation(row) do
      kept = Map.new(Oneiroi.AgathosDaimon.files(resident_id), &{&1.name, &1.content})
      gift = Enum.find(Oneiroi.AgathosDaimon.gifts(), &(&1.key == "trials"))
      model = Config.fetch!(:brain, :draft_model)

      system =
        Prompt.message("creation_trials", %{
          name: row.name,
          guidance: gift.guidance,
          existing: existing(kept, [])
        })

      ask = if String.trim(note) == "", do: "Suggest the trials.", else: note
      request = Request.new(model, [system, %{role: :user, content: ask}])

      with {:ok, %Result{content: reply} = result} <-
             Nisaba.call(resident_id, :drafting, request, actor),
           {:ok, trials} <- trials(reply || "") do
        {:ok, %{trials: trials, model: result.model || model}}
      end
    end
  end

  @doc "The trials in a reply: each with a prompt and what passing looks like; failing may be empty."
  @spec trials(String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def trials(reply) do
    with [_ | _] = found <- Regex.run(~r/\[.*\]/s, reply),
         {:ok, list} when is_list(list) <- Jason.decode(hd(found)),
         [_ | _] = trials <- Enum.flat_map(list, &trial/1) do
      {:ok, trials}
    else
      _unreadable ->
        {:error, Error.new(:brain_trials_unreadable, :brain_creation_trials_unreadable)}
    end
  end

  defp trial(%{"prompt" => p, "passes_if" => pass} = t) when is_binary(p) and is_binary(pass) do
    fail = if is_binary(t["fails_if"]), do: String.trim(t["fails_if"]), else: ""

    if String.trim(p) != "" and String.trim(pass) != "",
      do: [%{prompt: String.trim(p), passes_if: String.trim(pass), fails_if: fail}],
      else: []
  end

  defp trial(_other), do: []

  @doc """
  Reads one gift's draft (`content`, for identity file `file`) against
  that gift's guidance and records the read. Returns the notes with the
  read's ref, the draft's SHA-256 and the model. A refusal comes back as
  the model's words in `refused`, with no notes and nothing recorded.
  """
  @spec read(String.t(), String.t(), String.t(), Actor.t()) :: {:ok, map()} | {:error, term()}
  def read(resident_id, file, content, %Actor{} = actor) when is_binary(content) do
    with {:ok, row} <- fetch(resident_id),
         {:ok, gift} <- gift(file) do
      # Read by the resident's judge, the witness's choice of the
      # platform's (agathos-daimon#42): a reader from outside the drafting.
      model = Oneiroi.Eunomia.judge_model(resident_id)

      system =
        Prompt.message("creation_read", %{
          name: row.name,
          file: file,
          gift: gift.title,
          guidance: gift.guidance
        })

      request = Request.new(model, [system, %{role: :user, content: content}])
      sha = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      read = %{resident_id: resident_id, gift: gift, file: file, sha: sha, actor: actor}

      request
      |> then(&Nisaba.call(resident_id, :drafting, &1, actor))
      |> noted(read, content, model)
    end
  end

  defp noted({:ok, %Result{refusal?: true, content: words} = result}, read, _content, model),
    do: {:ok, answer(nil, read.gift, read.file, read.sha, [], result.model || model, words)}

  defp noted({:ok, %Result{content: reply} = result}, read, content, model) do
    used = result.model || model
    %{gift: gift, file: file, sha: sha} = read

    with {:ok, notes} <- notes(reply || "", content),
         {:ok, ref} <-
           Oneiroi.AgathosDaimon.record_gift_read(
             read.resident_id,
             %{gift: gift.key, file: file, draft_sha: sha, notes: notes, model: used},
             read.actor
           ),
         do: {:ok, answer(ref, gift, file, sha, notes, used, nil)}
  end

  defp noted({:error, reason}, _read, _content, _model), do: {:error, reason}

  defp answer(ref, gift, file, sha, notes, model, refused),
    do: %{
      ref: ref,
      gift: gift.key,
      file: file,
      draft_sha: sha,
      notes: notes,
      model: model,
      refused: refused
    }

  @doc false
  # Public for its test. The reply is a JSON array of notes, perhaps in a
  # code fence; a note of a kind not asked for, or with no words, is
  # dropped, and a quote not found in the draft word for word is dropped
  # from its note, so a read never shows the witness words he did not
  # write as his.
  @spec notes(String.t(), String.t()) :: {:ok, [note()]} | {:error, Error.t()}
  def notes(reply, draft) do
    kinds = Oneiroi.AgathosDaimon.note_kinds()

    with [_ | _] = found <- Regex.run(~r/\[.*\]/s, reply),
         {:ok, list} when is_list(list) <- Jason.decode(hd(found)) do
      {:ok, Enum.flat_map(list, &note(&1, kinds, draft))}
    else
      _unreadable ->
        {:error, Error.new(:brain_read_unreadable, :brain_creation_read_unreadable)}
    end
  end

  defp note(%{"kind" => kind, "text" => text} = n, kinds, draft)
       when is_binary(kind) and is_binary(text) do
    kind = kind |> String.trim() |> String.downcase()
    text = String.trim(text)

    if kind in kinds and text != "",
      do: [%{kind: kind, text: text, quote: quoted(n["quote"], draft)}],
      else: []
  end

  defp note(_other, _kinds, _draft), do: []

  defp quoted(q, draft) when is_binary(q) do
    q = String.trim(q)
    if q != "" and String.contains?(draft, q), do: q
  end

  defp quoted(_q, _draft), do: nil

  defp gift(file) do
    case file in Oneiroi.AgathosDaimon.identity_files() and Oneiroi.AgathosDaimon.gift_for(file) do
      %{} = gift ->
        {:ok, gift}

      _none ->
        {:error,
         Error.new(:brain_file_unknown, :brain_creation_read_file_unknown,
           files: Oneiroi.AgathosDaimon.identity_files()
         )}
    end
  end

  defp in_creation(%{first_contact_at: nil}), do: :ok

  defp in_creation(_row),
    do: {:error, Error.new(:brain_creation_closed, :brain_creation_generate_closed)}

  defp fetch(resident_id) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, row} ->
        {:ok, row}

      :error ->
        {:error,
         Error.new(:brain_no_such_resident, :brain_creation_resident_absent,
           resident_id: resident_id
         )}
    end
  end
end
