defmodule Oneiroi.Seshat.Index do
  @moduledoc """
  The index run (spec §6.5, F26): one vector index over every registered
  file of the resident's repository. Each run reads the document rows,
  hashes the files, and re-embeds only what changed, where a change is
  the file's hash or the platform-pinned model; a run with nothing
  changed costs three statements of its own (the rows read, the delete
  of edges from the kinds that never mint, the run row) and no model
  call, and the suite budgets exactly that. Every chunk of every changed
  file goes to the provider in one call under the `embeddings` purpose;
  a provider that fails writes nothing but the failed run.

  Edges are minted here, from the kinds the registry says cite, and
  resolved nowhere here: resolution is the read's (`Citations`).
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Nisaba
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Citations
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Seshat.Store
  alias Oneiroi.Seshat.Store.IndexRun
  alias Oneiroi.SimaQian

  @doc "Runs the index for a resident; returns the run's figures or the failure, recorded either way."
  # sobelow_skip ["Traversal.FileModule"]
  def run(resident_id, %Actor{} = actor) do
    model = Config.fetch!(:seshat, :embedding_model)

    with {:ok, dir} <- SimaQian.repository_dir(resident_id) do
      plan =
        resident_id
        |> Scope.resident(fn -> Store.documents() end)
        |> Enum.map(&plan(&1, dir, model))

      changed = for {:changed, doc, content} <- plan, do: {doc, content}
      texts = Enum.flat_map(changed, fn {doc, content} -> chunks_of(doc, content) end)

      case embed(resident_id, model, Enum.map(texts, &elem(&1, 1)), actor) do
        {:ok, vectors} ->
          write(resident_id, plan, Enum.zip(texts, vectors), model, actor)

        {:error, reason} ->
          record(
            resident_id,
            %IndexRun{
              outcome: "failed",
              reason: reason_text(reason),
              model: model,
              scanned: length(plan)
            },
            actor
          )

          {:error, Error.new(:seshat_index_failed, reason: reason_text(reason))}
      end
    end
  end

  @doc "The latest runs."
  def runs(resident_id, limit), do: Scope.resident(resident_id, fn -> Store.runs(limit) end)

  @doc "The nearest chunks to a query; an empty library answers empty with no model call."
  def search(resident_id, query, %Actor{} = actor) when is_binary(query) do
    model = Config.fetch!(:seshat, :embedding_model)
    limit = Config.fetch!(:seshat, :search_limit)

    cond do
      String.trim(query) == "" ->
        {:ok, []}

      not Scope.resident(resident_id, fn -> Store.any_chunks?() end) ->
        {:ok, []}

      true ->
        with {:ok, %{vectors: [vector]}} <- Nisaba.embed(resident_id, model, [query], actor) do
          {:ok, Scope.resident(resident_id, fn -> Store.nearest(vector, limit) end)}
        end
    end
  end

  @doc "A text in chunks of at most the bound, split on paragraphs; public so the split is testable."
  @spec chunk(String.t(), pos_integer()) :: [String.t()]
  def chunk(text, bound) when is_binary(text) and bound > 0 do
    text
    |> String.split(~r/\n\s*\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&split_long(&1, bound))
    |> Enum.reduce([], fn para, acc ->
      case acc do
        [current | rest] when byte_size(current) + byte_size(para) + 2 <= bound ->
          [current <> "\n\n" <> para | rest]

        _ ->
          [para | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp split_long(para, bound) when byte_size(para) <= bound, do: [para]

  defp split_long(para, bound) do
    para
    |> String.graphemes()
    |> Enum.chunk_every(bound)
    |> Enum.map(&Enum.join/1)
  end

  # ---- the plan ----

  # sobelow_skip ["Traversal.FileModule"]
  defp plan(doc, dir, model) do
    case File.read(Path.join(dir, doc.path)) do
      {:error, _} ->
        {:missing, doc}

      {:ok, content} ->
        hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

        if hash == doc.hash and doc.embedded_with == model and not is_nil(doc.indexed_at),
          do: {:same, doc},
          else: {:changed, doc, content}
    end
  end

  defp chunks_of(doc, content) do
    if Kinds.text?(doc.path) do
      {_front, body} = Citations.frontmatter(content)

      body
      |> chunk(Config.fetch!(:seshat, :chunk_chars))
      |> Enum.with_index(1)
      |> Enum.map(fn {text, i} -> {{doc.path, i}, text} end)
    else
      []
    end
  end

  defp embed(_resident_id, _model, [], _actor), do: {:ok, []}

  defp embed(resident_id, model, texts, actor) do
    width = Config.fetch!(:seshat, :embedding_width)

    with {:ok, %{vectors: vectors}} <- Nisaba.embed(resident_id, model, texts, actor) do
      cond do
        length(vectors) != length(texts) ->
          {:error, "the provider answered #{length(vectors)} vectors for #{length(texts)} chunks"}

        Enum.any?(vectors, &(length(&1) != width)) ->
          {:error,
           "the provider answered a width other than #{width}; the column is #{width} wide"}

        true ->
          {:ok, vectors}
      end
    end
  end

  # ---- the write ----

  defp write(resident_id, plan, embedded, model, actor) do
    now = Clock.now()
    by_path = Enum.group_by(embedded, fn {{{path, _i}, _text}, _vector} -> path end)

    figures =
      Scope.resident(resident_id, fn ->
        figures = fold_plan(resident_id, plan, by_path, model, now)
        Store.delete_references_of_kinds(Kinds.non_minting())

        run = %IndexRun{
          outcome: "ok",
          model: model,
          scanned: length(plan),
          embedded: figures.embedded,
          chunks: figures.chunks,
          missing: figures.missing
        }

        Store.insert_run(run_row(resident_id, actor, run))
        figures
      end)

    {:ok, Map.merge(figures, %{scanned: length(plan), model: model})}
  end

  defp fold_plan(resident_id, plan, by_path, model, now) do
    Enum.reduce(plan, %{embedded: 0, chunks: 0, missing: 0}, fn
      {:same, _doc}, acc ->
        acc

      {:missing, doc}, acc ->
        missing(doc, now, acc)

      {:changed, doc, content}, acc ->
        changed(resident_id, doc, content, Map.get(by_path, doc.path, []), model, now, acc)
    end)
  end

  defp missing(doc, now, acc) do
    Store.replace_chunks(doc.path, [])
    Store.replace_references(doc.path, [])
    Store.update_document(doc.path, missing_at: now, chunks: 0)
    %{acc | missing: acc.missing + 1}
  end

  defp changed(resident_id, doc, content, chunks, model, now, acc) do
    kind = Kinds.kind_of(doc.path)

    rows =
      Enum.map(chunks, fn {{{_path, i}, text}, vector} ->
        %{
          resident_id: resident_id,
          path: doc.path,
          ordinal: i,
          text: text,
          embedding: Pgvector.new(vector)
        }
      end)

    Store.replace_chunks(doc.path, rows)
    Store.replace_references(doc.path, reference_rows(resident_id, doc, kind, content))

    Store.update_document(doc.path,
      hash: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
      title: Citations.title(doc.path, content),
      status: Citations.status(kind, content),
      embedded_with: model,
      chunks: length(rows),
      indexed_at: now,
      missing_at: nil
    )

    %{acc | embedded: acc.embedded + 1, chunks: acc.chunks + length(rows)}
  end

  defp reference_rows(resident_id, doc, %{cites: true, kind: from_kind}, content) do
    if Kinds.text?(doc.path) do
      content
      |> Citations.extract()
      |> Enum.map(
        &%{
          resident_id: resident_id,
          from_path: doc.path,
          ordinal: &1.ordinal,
          from_kind: from_kind,
          target: &1.target,
          slug: &1.slug,
          kind: &1.kind,
          ref: &1.ref
        }
      )
    else
      []
    end
  end

  defp reference_rows(_resident_id, _doc, _kind, _content), do: []

  defp record(resident_id, %IndexRun{} = run, actor),
    do: Scope.resident(resident_id, fn -> Store.insert_run(run_row(resident_id, actor, run)) end)

  defp run_row(resident_id, actor, %IndexRun{} = run) do
    %{
      run
      | resident_id: resident_id,
        id: Ecto.UUID.generate(),
        at: Clock.now(),
        by_kind: Atom.to_string(actor.kind)
    }
  end

  defp reason_text(%{meaning: meaning}), do: meaning
  defp reason_text(text) when is_binary(text), do: text
  defp reason_text(other), do: inspect(other)
end
