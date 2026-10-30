defmodule OneiroiWeb.MemoryController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Ethos
  alias Oneiroi.Kumbukumbu
  alias OpenApiSpex.Schema

  tags(["memory"])

  plug(:witnessed)

  operation(:bookmarks,
    summary: "The resident's bookmarks, newest first, with their tags and pins",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"bookmarks", "application/json", %Schema{type: :array}}]
  )

  def bookmarks(conn, %{"id" => id}),
    do: json(conn, id |> Kumbukumbu.bookmarks() |> Enum.map(&bookmark/1))

  operation(:bookmark,
    summary: "One bookmark with the transcript of its span",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    responses: [ok: {"the bookmark and its span", "application/json", %Schema{type: :object}}]
  )

  def bookmark(conn, %{"id" => id, "number" => number}) do
    case Kumbukumbu.bookmark(id, integer(number)) do
      {:ok, b, span} -> json(conn, %{bookmark: bookmark(b), span: Enum.map(span, &message/1)})
      {:error, %Kumbukumbu.Error{} = e} -> error(conn, 404, e)
    end
  end

  operation(:pin,
    summary:
      "Pin a bookmark: a decision, recorded with who made it; with `evidences`, the soul line it is leaf-evidence of (spec §6.17)",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the evidence", "application/json",
       %Schema{type: :object, properties: %{evidences: %Schema{type: :integer}}}},
    responses: [no_content: "pinned"]
  )

  def pin(conn, %{"id" => id, "number" => number} = params) do
    case params["evidences"] do
      nil ->
        respond(conn, Kumbukumbu.pin_bookmark(id, integer(number), actor(conn)))

      line ->
        respond(conn, Ethos.pin_as_evidence(id, integer(number), integer(line), actor(conn)))
    end
  end

  operation(:unpin,
    summary: "Unpin a bookmark",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    responses: [no_content: "unpinned"]
  )

  def unpin(conn, %{"id" => id, "number" => number}),
    do: respond(conn, Kumbukumbu.unpin_bookmark(id, integer(number), actor(conn)))

  operation(:proposals,
    summary: "The open bookmark proposals awaiting the resident",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"proposals", "application/json", %Schema{type: :array}}]
  )

  def proposals(conn, %{"id" => id}),
    do: json(conn, id |> Kumbukumbu.proposals() |> Enum.map(&proposal/1))

  operation(:propose,
    summary:
      "Propose a bookmark on a turn with a suggested line; the resident writes or accepts it",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the proposal", "application/json",
       %Schema{
         type: :object,
         required: [:session_key, :anchor_ref, :line, :note],
         properties: %{
           session_key: %Schema{type: :string},
           anchor_ref: %Schema{type: :string},
           line: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [created: {"the proposal's ref", "application/json", %Schema{type: :object}}]
  )

  def propose(conn, %{
        "id" => id,
        "session_key" => key,
        "anchor_ref" => anchor,
        "line" => line,
        "note" => note
      }) do
    case Kumbukumbu.propose_bookmark(id, key, anchor, line, note, actor(conn)) do
      {:ok, ref} -> conn |> put_status(201) |> json(%{ref: ref})
      {:error, %{kind: _} = e} -> error(conn, 422, e)
      {:error, reason} -> problem(conn, 422, :not_proposed, inspect(reason))
    end
  end

  def propose(conn, _params),
    do:
      problem(conn, 422, :fields_required, "session_key, anchor_ref, line and note are required")

  operation(:tags,
    summary: "The tag set: active, proposed and retired",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"tags", "application/json", %Schema{type: :array}}]
  )

  def tags(conn, %{"id" => id}), do: json(conn, id |> Kumbukumbu.tags() |> Enum.map(&tag/1))

  operation(:create_tag,
    summary: "Add a tag to the set",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the slug", "application/json",
       %Schema{type: :object, required: [:slug], properties: %{slug: %Schema{type: :string}}}},
    responses: [created: "added"]
  )

  def create_tag(conn, %{"id" => id, "slug" => slug}) when is_binary(slug) do
    case Kumbukumbu.create_tag(id, slug, actor(conn)) do
      :ok -> send_resp(conn, 201, "")
      other -> respond(conn, other)
    end
  end

  def create_tag(conn, _params), do: problem(conn, 422, :slug_required, "slug is required")

  operation(:decide_tag,
    summary: "Approve or reject a proposed tag, with a note the resident reads first",
    parameters: [id: [in: :path, type: :string], slug: [in: :path, type: :string]],
    request_body:
      {"the decision", "application/json",
       %Schema{
         type: :object,
         required: [:decision, :note],
         properties: %{
           decision: %Schema{type: :string, enum: ["approve", "reject"]},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "decided"]
  )

  def decide_tag(conn, %{"id" => id, "slug" => slug, "decision" => decision, "note" => note})
      when decision in ["approve", "reject"] do
    result =
      case decision do
        "approve" -> Kumbukumbu.approve_tag(id, slug, note, actor(conn))
        "reject" -> Kumbukumbu.reject_tag(id, slug, note, actor(conn))
      end

    respond(conn, result)
  end

  def decide_tag(conn, _params),
    do: problem(conn, 422, :fields_required, "decision (approve or reject) and note are required")

  operation(:retire_tag,
    summary: "Retire a tag; what carried it keeps it",
    parameters: [id: [in: :path, type: :string], slug: [in: :path, type: :string]],
    responses: [no_content: "retired"]
  )

  def retire_tag(conn, %{"id" => id, "slug" => slug}),
    do: respond(conn, Kumbukumbu.retire_tag(id, slug, actor(conn)))

  operation(:tagged,
    summary: "Everything carrying a tag, across every record kind",
    parameters: [id: [in: :path, type: :string], slug: [in: :path, type: :string]],
    responses: [ok: {"taggings", "application/json", %Schema{type: :array}}]
  )

  def tagged(conn, %{"id" => id, "slug" => slug}),
    do: json(conn, id |> Kumbukumbu.tagged(slug) |> Enum.map(&tagging/1))

  operation(:apply_tag,
    summary: "Apply an active tag to a bookmark, a conversation or a turn",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the tagging", "application/json",
       %Schema{
         type: :object,
         required: [:tag, :target_kind, :target_id],
         properties: %{
           tag: %Schema{type: :string},
           target_kind: %Schema{type: :string, enum: ["bookmark", "conversation", "turn"]},
           target_id: %Schema{type: :string}
         }
       }},
    responses: [created: "applied"]
  )

  def apply_tag(conn, %{"id" => id, "tag" => tag, "target_kind" => kind, "target_id" => target}) do
    case Kumbukumbu.apply_tag(id, tag, kind, target, actor(conn)) do
      :ok -> send_resp(conn, 201, "")
      other -> respond(conn, other)
    end
  end

  def apply_tag(conn, _params),
    do: problem(conn, 422, :fields_required, "tag, target_kind and target_id are required")

  operation(:remove_tagging,
    summary: "Remove a tagging (tag, target_kind and target_id as query parameters)",
    parameters: [
      id: [in: :path, type: :string],
      tag: [in: :query, type: :string],
      target_kind: [in: :query, type: :string],
      target_id: [in: :query, type: :string]
    ],
    responses: [no_content: "removed"]
  )

  def remove_tagging(conn, %{
        "id" => id,
        "tag" => tag,
        "target_kind" => kind,
        "target_id" => target
      }),
      do: respond(conn, Kumbukumbu.remove_tagging(id, tag, kind, target, actor(conn)))

  def remove_tagging(conn, _params),
    do: problem(conn, 422, :fields_required, "tag, target_kind and target_id are required")

  operation(:revisions,
    summary: "Every revision (F13): corrections by either party with their reason and state",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"revisions", "application/json", %Schema{type: :array}}]
  )

  def revisions(conn, %{"id" => id}),
    do: json(conn, id |> Kumbukumbu.revisions() |> Enum.map(&revision/1))

  operation(:revise,
    summary:
      "Revise a memory: a fact applies at once, a stance is proposed to the resident; the note is why",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the revision", "application/json",
       %Schema{
         type: :object,
         required: [:target_kind, :target_id, :kind, :text, :note],
         properties: %{
           target_kind: %Schema{type: :string},
           target_id: %Schema{type: :string},
           kind: %Schema{type: :string, enum: ~w(fact stance)},
           text: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [
      ok: {"the revision's number and state", "application/json", %Schema{type: :object}}
    ]
  )

  def revise(conn, %{"id" => id} = params) do
    attrs = %{
      target_kind: to_string(params["target_kind"] || ""),
      target_id: to_string(params["target_id"] || ""),
      kind: to_string(params["kind"] || ""),
      text: to_string(params["text"] || ""),
      note: params["note"]
    }

    case Kumbukumbu.revise(id, attrs, actor(conn)) do
      {:ok, result} -> json(conn, result)
      other -> respond(conn, other)
    end
  end

  # Every route here is a resident's, read or written by its witness.
  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else: conn |> error(404, ResidentError.new(:agathos_daimon_not_witnessed)) |> halt()
  end

  defp revision(r) do
    %{
      number: r.number,
      target_kind: r.target_kind,
      target_id: r.target_id,
      kind: r.kind,
      text: r.text,
      note: r.note,
      state: r.state,
      by: %{kind: r.by_kind, id: r.by_id},
      at: r.at,
      decided_at: r.decided_at,
      decision_note: r.decision_note
    }
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [
              :kumbukumbu_no_such_bookmark,
              :kumbukumbu_no_such_tag,
              :kumbukumbu_no_such_proposal,
              :kumbukumbu_no_such_behaviour
            ],
       do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)
  defp respond(conn, {:error, reason}), do: problem(conn, 422, :refused, inspect(reason))

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> 0
    end
  end

  defp bookmark(b) do
    %{
      number: b.number,
      line: b.line,
      summary: b.summary,
      session_key: b.session_key,
      anchor_ref: b.anchor_ref,
      anchor_at: b.anchor_at,
      turns_back: b.turns_back,
      tags: b.tags,
      added_by: %{kind: b.added_by_kind, id: b.added_by_id, model: b.added_by_model},
      proposed_by: b.proposed_by_kind && %{kind: b.proposed_by_kind, id: b.proposed_by_id},
      pinned_by: b.pinned_by_kind && %{kind: b.pinned_by_kind, id: b.pinned_by_id},
      pin_evidences: b.pin_evidences,
      pinned_at: b.pinned_at,
      weight: b.weight,
      last_indexed_at: b.last_indexed_at,
      created_at: b.created_at
    }
  end

  defp proposal(p) do
    %{
      ref: p.ref,
      session_key: p.session_key,
      anchor_ref: p.anchor_ref,
      line: p.line,
      note: p.note,
      state: p.state,
      proposed_by: %{kind: p.proposed_by_kind, id: p.proposed_by_id},
      proposed_at: p.proposed_at
    }
  end

  defp tag(t),
    do: %{
      slug: t.slug,
      state: t.state,
      note: t.note,
      proposed_by: t.proposed_by_kind && %{kind: t.proposed_by_kind, id: t.proposed_by_id},
      created_at: t.created_at,
      decided_at: t.decided_at
    }

  defp tagging(t),
    do: %{
      tag: t.tag,
      target_kind: t.target_kind,
      target_id: t.target_id,
      applied_by: %{kind: t.applied_by_kind, id: t.applied_by_id},
      applied_at: t.applied_at
    }

  defp message(m) do
    %{
      session_key: m.session_key,
      turn_ref: m.turn_ref,
      role: m.role,
      content: m.content,
      sent_at: m.sent_at,
      actor: %{kind: m.actor_kind, id: m.actor_id, model: m.model},
      refusal: m.refusal
    }
  end
end
