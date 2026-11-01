defmodule OneiroiWeb.FileController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Ethos
  alias OpenApiSpex.Schema

  tags(["resident"])

  plug(:witnessed)

  operation(:index,
    summary: "The resident's identity files as last written, and the build-owned AGENTS.md",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"files", "application/json", %Schema{type: :array}}]
  )

  def index(conn, %{"id" => id}) do
    {:ok, agents} = AgathosDaimon.file(id, "AGENTS.md")
    rows = Enum.map(AgathosDaimon.files(id), &file/1) ++ [file(agents)]
    json(conn, rows)
  end

  operation(:show,
    summary: "One identity file",
    parameters: [id: [in: :path, type: :string], name: [in: :path, type: :string]],
    responses: [ok: {"the file", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id, "name" => name}) do
    case AgathosDaimon.file(id, name) do
      {:ok, row} -> json(conn, file(row))
      {:error, %{kind: _} = e} -> error(conn, 404, e)
    end
  end

  operation(:write,
    summary:
      "Write an identity file: a seed with its origin before first contact; after it, a proposal with a note",
    parameters: [id: [in: :path, type: :string], name: [in: :path, type: :string]],
    request_body:
      {"the file", "application/json",
       %Schema{
         type: :object,
         required: [:content],
         properties: %{
           content: %Schema{type: :string},
           origin: %Schema{type: :string, enum: ["authored", "drafted", "uploaded"]},
           model: %Schema{type: :string},
           prompt: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [
      no_content: "written",
      accepted: {"proposed: the ref", "application/json", %Schema{type: :object}}
    ]
  )

  def write(conn, %{"id" => id, "name" => name, "content" => content} = params)
      when is_binary(content) do
    attrs = %{
      origin: Map.get(params, "origin", "authored"),
      model: params["model"],
      prompt: params["prompt"]
    }

    case AgathosDaimon.write_file(id, name, content, attrs, actor(conn)) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, %{kind: :agathos_daimon_propose_instead}} ->
        propose(conn, id, name, content, params["note"])

      {:error, %{kind: _} = e} ->
        error(conn, 422, e)

      {:error, reason} ->
        problem(conn, 422, :not_written, :web_file_write_not_written, inspect(reason))
    end
  end

  def write(conn, _params),
    do:
      problem(
        conn,
        422,
        :content_required,
        :web_file_write_content_required,
        "content is required"
      )

  defp propose(conn, _id, _name, _content, nil),
    do:
      problem(
        conn,
        422,
        :note_required,
        :web_file_propose_note_required,
        "after first contact an edit is a proposal and needs a note"
      )

  defp propose(conn, id, name, content, note) do
    case AgathosDaimon.propose_edit(id, name, content, note, actor(conn)) do
      {:ok, ref} ->
        conn |> put_status(202) |> json(%{ref: ref})

      {:error, %{kind: _} = e} ->
        error(conn, 422, e)

      {:error, reason} ->
        problem(conn, 422, :not_proposed, :web_file_propose_not_proposed, inspect(reason))
    end
  end

  operation(:draft,
    summary:
      "Write it with me: a draft of the file from a prompt, billed as drafting; returned, not written",
    parameters: [id: [in: :path, type: :string], name: [in: :path, type: :string]],
    request_body:
      {"the prompt", "application/json",
       %Schema{type: :object, required: [:prompt], properties: %{prompt: %Schema{type: :string}}}},
    responses: [
      ok: {"the draft with its model and prompt", "application/json", %Schema{type: :object}}
    ]
  )

  def draft(conn, %{"id" => id, "name" => name, "prompt" => prompt}) when is_binary(prompt) do
    case Oneiroi.Brain.draft(id, name, prompt, actor(conn)) do
      {:ok, draft} ->
        json(conn, draft)

      {:error, %{kind: _} = e} ->
        error(conn, 422, e)

      {:error, reason} ->
        problem(conn, 422, :not_drafted, :web_file_draft_not_drafted, inspect(reason))
    end
  end

  def draft(conn, _params),
    do:
      problem(conn, 422, :prompt_required, :web_file_draft_prompt_required, "prompt is required")

  operation(:proposals,
    summary: "The open edit proposals awaiting the resident",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"proposals", "application/json", %Schema{type: :array}}]
  )

  def proposals(conn, %{"id" => id}),
    do: json(conn, id |> AgathosDaimon.edit_proposals() |> Enum.map(&proposal/1))

  operation(:soul_lines,
    summary:
      "The soul file's lines in order, each with its stable number, its words and the seeds it cites (spec §6.17)",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"lines", "application/json", %Schema{type: :array}}]
  )

  operation(:self_letters,
    summary:
      "The resident's letters to its next self and every receipt (spec §12, P41): this read leaves one, so the resident sees it was read",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"letters and receipts", "application/json", %Schema{type: :object}}]
  )

  def self_letters(conn, %{"id" => id}) do
    case AgathosDaimon.read_self_letters(id, actor(conn)) do
      {:ok, %{letters: letters, receipts: receipts}} ->
        json(conn, %{
          letters: Enum.map(letters, &self_letter/1),
          receipts: Enum.map(receipts, &receipt/1)
        })

      {:error, reason} ->
        error(conn, 422, reason)
    end
  end

  defp self_letter(l) do
    %{
      number: l.number,
      text: l.text,
      model: l.model,
      written_at: l.written_at,
      delivered_at: l.delivered_at,
      delivered_to: l.delivered_to
    }
  end

  defp receipt(r), do: %{at: r.at, by_kind: r.by_kind, by_id: r.by_id, numbers: r.numbers}

  def soul_lines(conn, %{"id" => id}) do
    evidence = id |> Ethos.soul_evidence() |> Enum.group_by(& &1.number)
    json(conn, id |> AgathosDaimon.soul_lines() |> Enum.map(&soul_line(&1, evidence)))
  end

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else: conn |> error(404, ResidentError.new(:agathos_daimon_not_witnessed)) |> halt()
  end

  defp soul_line(l, evidence) do
    cited = Map.get(evidence, l.number, [])

    %{
      number: l.number,
      text: l.text,
      position: l.position,
      cites: l.cites,
      version: l.version,
      written_at: l.written_at,
      reworded_at: l.reworded_at,
      citations: length(cited),
      days: cited |> Enum.map(&DateTime.to_date(&1.at)) |> Enum.uniq() |> length()
    }
  end

  defp file(f) do
    %{
      name: f.name,
      content: f.content,
      origin: f.origin,
      model: Map.get(f, :model),
      prompt: Map.get(f, :prompt),
      version: Map.get(f, :version),
      written_by:
        if(Map.get(f, :written_by_kind),
          do: %{kind: f.written_by_kind, id: f.written_by_id},
          else: nil
        ),
      written_at: Map.get(f, :written_at)
    }
  end

  defp proposal(p) do
    %{
      ref: p.ref,
      file: p.file,
      content: p.content,
      note: p.note,
      state: p.state,
      proposed_by: %{kind: p.proposed_by_kind, id: p.proposed_by_id},
      proposed_at: p.proposed_at
    }
  end
end
