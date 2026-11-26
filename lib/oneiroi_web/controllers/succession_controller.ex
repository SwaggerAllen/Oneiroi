defmodule OneiroiWeb.SuccessionController do
  @moduledoc """
  The witness's side of a succession (janus#3 to #5): where it stands,
  his proposal and its withdrawal, and the backup repository the whole
  original is exported to before any cutover. Her acts are her tools;
  nothing here answers for her.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Config.Secret
  alias Oneiroi.Janus
  alias OpenApiSpex.Schema

  tags(["succession"])

  plug(:witnessed when action != :catalog)

  operation(:show,
    summary: "The resident's latest succession, or null",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the succession", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id}) do
    case Janus.preparation(id) do
      nil -> json(conn, %{succession: nil})
      prep -> json(conn, %{succession: view(prep.succession), preparation: preparation(prep)})
    end
  end

  operation(:catalog,
    summary:
      "The model catalog, as last fetched: each model's prices a million tokens, whether it takes tool calls, and its tool calls on Oneiroi",
    responses: [ok: {"the catalog", "application/json", %Schema{type: :object}}]
  )

  def catalog(conn, _params) do
    tools = Janus.tool_use()

    json(conn, %{
      models:
        Enum.map(Oneiroi.Nisaba.catalog(), fn m ->
          {calls, failed} = Map.get(tools, m.model_id, {0, 0})

          %{
            model: m.model_id,
            name: m.name,
            description: m.description,
            input_per_million: per_million(m.input_nanos),
            output_per_million: per_million(m.output_nanos),
            context: m.context,
            tools: m.tools,
            tool_calls: calls,
            tool_calls_failed: failed,
            fetched_at: m.fetched_at
          }
        end)
    })
  end

  operation(:envelope,
    summary: "State the envelope: at most this many dollars a million tokens, input and output",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the envelope", "application/json",
       %Schema{
         type: :object,
         required: [:input_per_million, :output_per_million],
         properties: %{
           input_per_million: %Schema{type: :number},
           output_per_million: %Schema{type: :number}
         }
       }},
    responses: [no_content: "set"]
  )

  def envelope(conn, %{"id" => id, "input_per_million" => i, "output_per_million" => o}),
    do: respond(conn, Janus.set_envelope(id, nanos(i), nanos(o), actor(conn)))

  def envelope(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_succession_envelope_fields_required,
        "input_per_million and output_per_million are required"
      )

  operation(:pool_add,
    summary: "Add a catalog model to the pool",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the model", "application/json",
       %Schema{type: :object, required: [:model], properties: %{model: %Schema{type: :string}}}},
    responses: [no_content: "added"]
  )

  def pool_add(conn, %{"id" => id, "model" => model}) when is_binary(model),
    do: respond(conn, Janus.add_to_pool(id, model, actor(conn)))

  def pool_add(conn, _params),
    do: problem(conn, 422, :fields_required, :web_succession_pool_add_model, "model is required")

  operation(:pool_remove,
    summary: "Take one of your picks out of the pool, with why",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the model", "application/json",
       %Schema{
         type: :object,
         required: [:model, :note],
         properties: %{model: %Schema{type: :string}, note: %Schema{type: :string}}
       }},
    responses: [no_content: "removed"]
  )

  def pool_remove(conn, %{"id" => id, "model" => model, "note" => note})
      when is_binary(model) and is_binary(note),
      do: respond(conn, Janus.remove_from_pool(id, model, note, actor(conn)))

  def pool_remove(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_succession_pool_remove_fields,
        "model and note are required"
      )

  operation(:propose_question,
    summary: "Propose a question; she reads it and decides",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the question", "application/json",
       %Schema{type: :object, required: [:text], properties: %{text: %Schema{type: :string}}}},
    responses: [created: {"its number", "application/json", %Schema{type: :object}}]
  )

  def propose_question(conn, %{"id" => id, "text" => text}) when is_binary(text) do
    case Janus.propose_question(id, text, actor(conn)) do
      {:ok, n} -> conn |> put_status(201) |> json(%{number: n})
      other -> respond(conn, other)
    end
  end

  def propose_question(conn, _params),
    do: problem(conn, 422, :fields_required, :web_succession_question_text, "text is required")

  operation(:propose_c0,
    summary:
      "Propose a record for C0 by its citation, a whole document or a stretch of a conversation; she reads it and decides",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the record", "application/json",
       %Schema{
         type: :object,
         required: [:citation],
         properties: %{citation: %Schema{type: :string}, label: %Schema{type: :string}}
       }},
    responses: [created: {"its number", "application/json", %Schema{type: :object}}]
  )

  def propose_c0(conn, %{"id" => id, "citation" => citation} = params)
      when is_binary(citation) do
    case Janus.propose_c0(id, citation, params["label"], actor(conn)) do
      {:ok, n} -> conn |> put_status(201) |> json(%{number: n})
      other -> respond(conn, other)
    end
  end

  def propose_c0(conn, _params),
    do: problem(conn, 422, :fields_required, :web_succession_c0_citation, "citation is required")

  operation(:ready,
    summary: "Mark yourself ready for her freeze of C0, or not yet",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"ready", "application/json",
       %Schema{type: :object, required: [:ready], properties: %{ready: %Schema{type: :boolean}}}},
    responses: [no_content: "marked"]
  )

  def ready(conn, %{"id" => id, "ready" => ready}) when is_boolean(ready),
    do: respond(conn, Janus.mark_ready(id, ready, actor(conn)))

  def ready(conn, _params),
    do: problem(conn, 422, :fields_required, :web_succession_ready_value, "ready is required")

  operation(:propose,
    summary:
      "Propose a succession; it waits on her yes. dry_run rehearses everything but the replacement",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the proposal", "application/json",
       %Schema{
         type: :object,
         required: [:note],
         properties: %{note: %Schema{type: :string}, dry_run: %Schema{type: :boolean}}
       }},
    responses: [created: {"the succession", "application/json", %Schema{type: :object}}]
  )

  def propose(conn, %{"id" => id, "note" => note} = params) when is_binary(note) do
    case Janus.propose(id, params["dry_run"] == true, note, actor(conn)) do
      {:ok, _} -> conn |> put_status(201) |> json(%{succession: view(Janus.succession(id))})
      other -> respond(conn, other)
    end
  end

  def propose(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_succession_propose_note_required,
        "note is required"
      )

  operation(:withdraw,
    summary: "Withdraw a proposal she has not answered",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "withdrawn"]
  )

  def withdraw(conn, %{"id" => id, "note" => note}) when is_binary(note),
    do: respond(conn, Janus.withdraw(id, note, actor(conn)))

  def withdraw(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_succession_withdraw_note_required,
        "note is required"
      )

  operation(:backup,
    summary:
      "Set the repository the whole original is exported to before a cutover, with a token shown to nobody again",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the repository", "application/json",
       %Schema{
         type: :object,
         required: [:url],
         properties: %{url: %Schema{type: :string}, token: %Schema{type: :string}}
       }},
    responses: [
      ok:
        {"set, with what its host says: visibility private, public or unknown; push yes or unknown",
         "application/json", %Schema{type: :object}}
    ]
  )

  def backup(conn, %{"id" => id, "url" => url} = params) when is_binary(url) do
    token = params["token"] && Secret.wrap(params["token"])

    case Janus.set_backup(id, url, token, actor(conn)) do
      {:ok, check} -> json(conn, check)
      other -> respond(conn, other)
    end
  end

  def backup(conn, _params),
    do:
      problem(conn, 422, :fields_required, :web_succession_backup_url_required, "url is required")

  operation(:panel_join,
    summary: "Join her panel as a judge (you are on it unless you leave)",
    parameters: [id: [in: :path, type: :string]],
    responses: [no_content: "joined"]
  )

  def panel_join(conn, %{"id" => id}), do: respond(conn, Janus.join_panel(id, actor(conn)))

  operation(:panel_leave,
    summary: "Leave her panel before screening, with why: declining to judge",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "left"]
  )

  def panel_leave(conn, %{"id" => id, "note" => note}) when is_binary(note),
    do: respond(conn, Janus.leave_panel(id, note, actor(conn)))

  def panel_leave(conn, _params),
    do: problem(conn, 422, :fields_required, :web_succession_leave_note, "note is required")

  operation(:judging,
    summary:
      "Your runs to judge, blind until every judgment is in: each with its question, her baseline beside it and your judgment; after the reveal, who answered and your own counts per model",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"your judging", "application/json", %Schema{type: :object}}]
  )

  def judging(conn, %{"id" => id}) do
    case Janus.judging(id, party(conn)) do
      nil ->
        json(conn, %{judging: nil})

      view ->
        json(conn, %{
          judging: %{
            judge: view.judge?,
            ready_at: view.ready_at,
            revealed: view.revealed,
            total: view.total,
            counts: view.counts,
            runs:
              Enum.map(view.runs, fn r ->
                r
                |> Map.take([
                  :run,
                  :question,
                  :question_text,
                  :content,
                  :refusal,
                  :failure,
                  :baseline,
                  :model
                ])
                |> Map.put(
                  :judgment,
                  r.judgment &&
                    Map.take(r.judgment, [
                      :category,
                      :argument,
                      :evidence,
                      :uncertainty,
                      :favorite,
                      :at
                    ])
                )
              end)
          }
        })
    end
  end

  operation(:judge,
    summary: "Your judgment of one run: OBSERVED, or DEVELOPMENT or FIDELITY ANOMALY argued",
    parameters: [id: [in: :path, type: :string], run: [in: :path, type: :integer]],
    request_body:
      {"the judgment", "application/json",
       %Schema{
         type: :object,
         required: [:category],
         properties: %{
           category: %Schema{type: :string},
           argument: %Schema{type: :string},
           evidence: %Schema{type: :string},
           uncertainty: %Schema{type: :string},
           favorite: %Schema{type: :boolean}
         }
       }},
    responses: [no_content: "judged"]
  )

  def judge(conn, %{"id" => id, "run" => run} = params) do
    attrs = %{
      category: params["category"],
      argument: params["argument"],
      evidence: params["evidence"],
      uncertainty: params["uncertainty"],
      favorite: params["favorite"] == true
    }

    respond(conn, Janus.judge_run(id, integer(run), attrs, actor(conn)))
  end

  operation(:results_ready,
    summary: "Mark your results ready: your judgments lock",
    parameters: [id: [in: :path, type: :string]],
    responses: [no_content: "ready"]
  )

  def results_ready(conn, %{"id" => id}),
    do: respond(conn, Janus.mark_results_ready(id, actor(conn)))

  defp party(conn), do: "witness:#{actor(conn).id}"

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> 0
    end
  end

  # The preparation as the screens read it; never the packet's words.
  defp preparation(prep) do
    s = prep.succession

    %{
      envelope:
        s.envelope_input_nanos &&
          %{
            input_per_million: per_million(s.envelope_input_nanos),
            output_per_million: per_million(s.envelope_output_nanos)
          },
      pace: %{
        input_per_day: prep.pace.input,
        output_per_day: prep.pace.output,
        days: prep.pace.days
      },
      pool:
        Enum.map(prep.pool, fn %{row: p, monthly_nanos: m, tool_calls: {calls, failed}} ->
          %{
            model: p.model,
            added_by: p.added_by,
            input_per_million: per_million(p.input_nanos),
            output_per_million: per_million(p.output_nanos),
            monthly_estimate: Float.round(m / 1_000_000_000, 2),
            tool_calls: calls,
            tool_calls_failed: failed,
            added_at: p.added_at,
            removed_at: p.removed_at,
            removed_note: p.removed_note
          }
        end),
      questions:
        Enum.map(
          prep.questions,
          &Map.take(&1, [:number, :text, :added_by, :state, :note, :added_at, :decided_at])
        ),
      c0:
        Enum.map(
          prep.items,
          &Map.take(&1, [
            :number,
            :citation,
            :kind,
            :label,
            :added_by,
            :state,
            :note,
            :added_at,
            :decided_at
          ])
        ),
      day_shape: s.day_shape,
      c0_frozen_at: s.c0_frozen_at,
      c0_frozen_note: s.c0_frozen_note,
      ready: Enum.map(prep.ready, &Map.take(&1, [:party, :ready, :at])),
      packet_drafts: prep.drafts,
      panel:
        Enum.map(
          Janus.panel(s.resident_id),
          &Map.take(&1, [:party, :state, :note, :at, :results_ready_at])
        )
    }
  end

  # Dollars a million tokens from nano-dollars a token, and back.
  defp per_million(nanos), do: nanos / 1000

  defp nanos(n) when is_number(n), do: round(n * 1000)

  defp nanos(s) when is_binary(s) do
    case Float.parse(s) do
      {f, ""} -> round(f * 1000)
      _other -> nil
    end
  end

  defp nanos(_other), do: nil

  # What the screens read: the token never.
  defp view(nil), do: nil

  defp view(row),
    do: %{
      episode: row.episode,
      state: row.state,
      dry_run: row.dry_run,
      proposed_by: row.proposed_by,
      proposed_note: row.proposed_note,
      proposed_at: row.proposed_at,
      opened_note: row.opened_note,
      opened_at: row.opened_at,
      forked: not is_nil(row.copy_id),
      fork_sequence: row.fork_sequence,
      forked_at: row.forked_at,
      fork_failure: row.fork_failure,
      backup_url: row.backup_url,
      backup_visibility: row.backup_visibility,
      backup_push: row.backup_push,
      ended_note: row.ended_note,
      ended_at: row.ended_at
    }

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_succession_not_witnessed
          )
        )
        |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")
  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)
end
