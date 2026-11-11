defmodule OneiroiWeb.MemoryController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Ethos
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["memory"])

  plug(:witnessed)
  # The contract's switches (agathos-daimon#34), after the party check.
  plug(OneiroiWeb.Plugs.Switch, [key: "witness_reads"] when action in [:bookmarks, :bookmark])
  plug(OneiroiWeb.Plugs.Switch, [key: "revisions"] when action in [:revise])

  operation(:bookmarks,
    summary:
      "The resident's bookmarks, newest first, with their tags and pins: with no query, every one as an array; with any of `before` (a bookmark number), `limit` (default 50, at most 500), `from` and `to` (each an ISO date, a whole day in her zone, or an ISO instant; `to` exclusive for an instant), a page `{bookmarks, more}`, `more` saying whether older ones remain (kumbukumbu#57). Each row's `session_key` and `anchor_ref` link to the moment; one made in a private session she has not shared is `private: true` with its `line`, `summary` and `register` null (kumbukumbu#62)",
    parameters: [
      id: [in: :path, type: :string],
      before: [in: :query, type: :integer],
      limit: [in: :query, type: :integer],
      from: [in: :query, type: :string],
      to: [in: :query, type: :string]
    ],
    responses: [
      ok: {"bookmarks, or a page of them", "application/json", %Schema{type: :object}},
      unprocessable_entity:
        {"a bound that is no date or instant", "application/json", %Schema{type: :object}}
    ]
  )

  @page_params ~w(before limit from to)

  # Unpaged when no paging parameter is given: the shape every client
  # before kumbukumbu#57 reads.
  def bookmarks(conn, %{"id" => id} = params) do
    if Enum.any?(@page_params, &Map.has_key?(params, &1)),
      do: bookmarks_page(conn, id, params),
      else: json(conn, id |> Kumbukumbu.witness_bookmarks() |> Enum.map(&bookmark/1))
  end

  defp bookmarks_page(conn, id, params) do
    limit = params["limit"] |> positive() |> Kernel.||(50) |> min(500)

    case Kumbukumbu.day_range(id, params["from"], params["to"]) do
      {:ok, from, to} ->
        {rows, more} =
          Kumbukumbu.witness_bookmarks_page(id, positive(params["before"]), limit, from, to)

        json(conn, %{bookmarks: Enum.map(rows, &bookmark/1), more: more})

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  operation(:density,
    summary:
      "The navigator's track (kumbukumbu#58): per local day in the resident's zone from `from` to `to` (ISO dates, both included; the last 30 days through today by default; at most 366), how many bookmarks, scenes (seshat#52, corrections not counted) and messages it holds, every day of the range, oldest first. Messages are those of the sessions the witness sees, of one session when `session` names it. `{from, to, zone, days: [{day, bookmarks, scenes, messages}]}`",
    parameters: [
      id: [in: :path, type: :string],
      from: [in: :query, type: :string],
      to: [in: :query, type: :string],
      session: [in: :query, type: :string]
    ],
    responses: [
      ok: {"the counts", "application/json", %Schema{type: :object}},
      unprocessable_entity:
        {"a range that is no range", "application/json", %Schema{type: :object}}
    ]
  )

  def density(%{assigns: %{principal: p}} = conn, %{"id" => id} = params) do
    case Kumbukumbu.day_counts(
           {:account, p.account_id},
           id,
           params["from"],
           params["to"],
           params["session"]
         ) do
      {:ok, counts} ->
        scenes = Seshat.scene_counts(id, counts.from, counts.to)

        days =
          for d <- counts.days,
              do: %{
                day: d.day,
                bookmarks: d.bookmarks,
                scenes: Map.get(scenes, d.day, 0),
                messages: d.messages
              }

        json(conn, %{counts | days: days})

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  operation(:index_now,
    summary:
      "What the index holds now in the common room (kumbukumbu#38): the bookmark numbers listed, in order, `private` the listed numbers made in a private session she has not shared (kumbukumbu#62: numbers only, as everywhere here), the left-out count, the count kept to named rooms, and a sentence saying it",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the index", "application/json", %Schema{type: :object}}]
  )

  def index_now(conn, %{"id" => id}) do
    now = Kumbukumbu.index_now(id)

    json(conn, %{
      listed: now.listed,
      private: now.private,
      left_out: now.left_out,
      elsewhere: now.elsewhere,
      description: now.description
    })
  end

  operation(:send_letter,
    summary:
      "The witness writes a house letter (kumbukumbu#44): to a conversation by its name, to Free time (a brief for the next free time), or to house; sent as `witness`",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the letter", "application/json",
       %Schema{
         type: :object,
         required: [:to, :text],
         properties: %{
           to: %Schema{type: :string},
           text: %Schema{type: :string},
           in_reply_to: %Schema{type: :integer, nullable: true}
         }
       }},
    responses: [created: {"the letter's number", "application/json", %Schema{type: :object}}]
  )

  def send_letter(conn, %{"id" => id} = params) do
    attrs = %{
      to: to_string(params["to"] || ""),
      text: to_string(params["text"] || ""),
      in_reply_to: params["in_reply_to"]
    }

    case Kumbukumbu.send_letter(id, nil, attrs, actor(conn)) do
      {:ok, %{number: n}} -> conn |> put_status(201) |> json(%{number: n})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:letter_addresses,
    summary: "The names a house letter can be addressed to",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the names", "application/json", %Schema{type: :array}}]
  )

  def letter_addresses(conn, %{"id" => id}), do: json(conn, Kumbukumbu.letter_addresses(id))

  operation(:letters,
    summary:
      "The house letters (kumbukumbu#44): the work log between the resident's conversations, every letter both ways, oldest first, with who sent it, to whom, in reply to what, the keepsake it gives and the conversations that have read it",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the letters", "application/json", %Schema{type: :array}}]
  )

  def letters(conn, %{"id" => id}) do
    json(
      conn,
      Enum.map(Kumbukumbu.letters(id), fn l ->
        %{
          number: l.number,
          from: l.from_name,
          to: l.to_name,
          in_reply_to: l.in_reply_to,
          text: l.text,
          keepsake: l.keepsake,
          sent_at: l.sent_at,
          read_by: Enum.uniq(l.read_by),
          read_at: l.read_at
        }
      end)
    )
  end

  operation(:retrieval,
    summary:
      "How retrieval has been used, target by target (kumbukumbu#43): each target in citation form with how often it was considered, returned and used, and when last returned and used; `kind` narrows to one kind. The same numbers the resident reads with memory_use: the audit is two-party",
    parameters: [id: [in: :path, type: :string], kind: [in: :query, type: :string]],
    responses: [ok: {"the counts", "application/json", %Schema{type: :array}}]
  )

  def retrieval(conn, %{"id" => id} = params) do
    rows = Kumbukumbu.retrieval({:resident, id}, kind: params["kind"])

    json(
      conn,
      rows
      |> Enum.sort_by(&{-&1.used, -&1.returned, &1.target})
      |> Enum.map(
        &Map.take(&1, [
          :target,
          :considered,
          :returned,
          :used,
          :last_returned_at,
          :last_used_at
        ])
      )
    )
  end

  operation(:bookmark,
    summary:
      "One bookmark with the transcript of its span; one made in a private session she has not shared is `private: true`, its words null and its span `[]` (kumbukumbu#62)",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    responses: [ok: {"the bookmark and its span", "application/json", %Schema{type: :object}}]
  )

  def bookmark(conn, %{"id" => id, "number" => number}) do
    case Kumbukumbu.witness_bookmark(id, integer(number)) do
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
    summary:
      "Your bookmark proposals (kumbukumbu#63): `state` open (the default, the array every earlier client reads), answered (accepted or declined) or all, oldest first. An answered one carries `answer` `{decision, note, at, bookmark}`: declined with her note; accepted with `bookmark`, the one she wrote for it (`{number, line, summary, private}`, its words null when it sits in a private session she has not shared, kumbukumbu#62) and no note, the words being her answer",
    parameters: [
      id: [in: :path, type: :string],
      state: [in: :query, type: :string]
    ],
    responses: [
      ok: {"proposals", "application/json", %Schema{type: :array}},
      unprocessable_entity: {"a state not listed", "application/json", %Schema{type: :object}}
    ]
  )

  def proposals(conn, %{"id" => id} = params) do
    case proposal_state(params["state"]) do
      {:ok, which} ->
        rows = Kumbukumbu.proposals(id, which)

        kept =
          if Enum.any?(rows, &(&1.state == "accepted")),
            do: Map.new(Kumbukumbu.witness_bookmarks(id), &{&1.number, &1}),
            else: %{}

        json(conn, Enum.map(rows, &proposal(&1, kept)))

      :error ->
        problem(
          conn,
          422,
          :state_unknown,
          :web_memory_proposals_state_unknown,
          "state is one of open, answered or all"
        )
    end
  end

  defp proposal_state(nil), do: {:ok, :open}
  defp proposal_state("open"), do: {:ok, :open}
  defp proposal_state("answered"), do: {:ok, :answered}
  defp proposal_state("all"), do: {:ok, :all}
  defp proposal_state(_other), do: :error

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
      {:ok, ref} ->
        conn |> put_status(201) |> json(%{ref: ref})

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  def propose(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_memory_propose_fields_required,
        "session_key, anchor_ref, line and note are required"
      )

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

  def create_tag(conn, _params),
    do:
      problem(conn, 422, :slug_required, :web_memory_create_tag_slug_required, "slug is required")

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
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_memory_decide_tag_fields_required,
        "decision (approve or reject) and note are required"
      )

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
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_memory_apply_tag_fields_required,
        "tag, target_kind and target_id are required"
      )

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
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_memory_remove_tagging_fields_required,
        "tag, target_kind and target_id are required"
      )

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
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_memory_not_witnessed
          )
        )
        |> halt()
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

  defp respond(conn, {:error, e}), do: error(conn, 422, e)

  # A paging number: a positive integer, else none (the newest page, the
  # default size), as a `before` that is no cursor reads in the chat.
  defp positive(n) when is_integer(n) and n > 0, do: n

  defp positive(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n > 0 -> n
      _other -> nil
    end
  end

  defp positive(_other), do: nil

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
      register: b.register,
      private: b.private,
      pinned_at: b.pinned_at,
      weight: b.weight,
      last_indexed_at: b.last_indexed_at,
      created_at: b.created_at
    }
  end

  defp proposal(p, kept) do
    %{
      ref: p.ref,
      session_key: p.session_key,
      anchor_ref: p.anchor_ref,
      line: p.line,
      note: p.note,
      state: p.state,
      proposed_by: %{kind: p.proposed_by_kind, id: p.proposed_by_id},
      proposed_at: p.proposed_at,
      answer: answer(p, kept)
    }
  end

  # Her answer (kumbukumbu#63): a decline's note, or the bookmark she
  # wrote in accepting, its words withheld where the session is locked.
  defp answer(%{state: "declined"} = p, _kept),
    do: %{decision: "declined", note: p.decided_note, at: p.decided_at, bookmark: nil}

  defp answer(%{state: "accepted"} = p, kept) do
    %{
      decision: "accepted",
      note: nil,
      at: p.decided_at,
      bookmark:
        case kept[p.bookmark_number] do
          nil ->
            nil

          b ->
            %{number: b.number, line: b.line, summary: b.summary, private: b.private}
        end
    }
  end

  defp answer(_open, _kept), do: nil

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
