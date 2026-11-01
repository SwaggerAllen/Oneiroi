defmodule OneiroiWeb.CharacterController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Ethos
  alias OpenApiSpex.Schema

  tags(["character"])

  plug(:witnessed)

  operation(:habits,
    summary: "The resident's habits with their habit and connection scores, ranked (spec §6.17)",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"habits", "application/json", %Schema{type: :array}}]
  )

  def habits(conn, %{"id" => id}), do: json(conn, id |> Ethos.habits() |> Enum.map(&habit/1))

  operation(:define_habit,
    summary: "Give a first habit before first contact (after it the resident names its own)",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the habit", "application/json",
       %Schema{
         type: :object,
         required: [:name],
         properties: %{
           name: %Schema{type: :string},
           trigger: %Schema{type: :object},
           stance: %Schema{type: :string, enum: ["keep", "change"]}
         }
       }},
    responses: [created: {"the number", "application/json", %Schema{type: :object}}]
  )

  def define_habit(conn, %{"id" => id, "name" => name} = params) do
    attrs = %{name: name, trigger: Map.get(params, "trigger", %{}), stance: params["stance"]}

    case Ethos.define_habit(id, attrs, actor(conn)) do
      {:ok, number} -> conn |> put_status(201) |> json(%{number: number})
      other -> respond(conn, other)
    end
  end

  def define_habit(conn, _params),
    do:
      problem(
        conn,
        422,
        :name_required,
        :web_character_define_habit_name_required,
        "name is required"
      )

  operation(:affirm_habit,
    summary: "Affirm a habit, with a note the resident reads",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the note", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "affirmed"]
  )

  def affirm_habit(conn, %{"id" => id, "number" => number, "note" => note}),
    do: respond(conn, Ethos.affirm_habit(id, integer(number), note, actor(conn)))

  def affirm_habit(conn, _params),
    do:
      problem(
        conn,
        422,
        :note_required,
        :web_character_affirm_habit_note_required,
        "note is required"
      )

  operation(:seeds,
    summary:
      "The resident's seeds, open and closed, with their citations: the witness reads, never writes (spec §6.17)",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"seeds", "application/json", %Schema{type: :array}}]
  )

  def seeds(conn, %{"id" => id}), do: json(conn, id |> Ethos.seeds() |> Enum.map(&seed/1))

  operation(:commitments,
    summary:
      "The resident's commitments, open and closed (spec §3.1, P19): the witness reads them and may release one",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"commitments", "application/json", %Schema{type: :array}}]
  )

  def commitments(conn, %{"id" => id}),
    do: json(conn, id |> Ethos.commitments() |> Enum.map(&commitment/1))

  operation(:release_commitment,
    summary: "Release the resident from a commitment made to you, with a note",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the note", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "released"]
  )

  def release_commitment(conn, %{"id" => id, "number" => number, "note" => note}),
    do: respond(conn, Ethos.release_commitment(id, integer(number), note, actor(conn)))

  def release_commitment(conn, _params),
    do:
      problem(
        conn,
        422,
        :note_required,
        :web_character_release_commitment_note_required,
        "note is required"
      )

  operation(:baselines,
    summary:
      "The trait baselines, newest first: the habits' profile as measured, the spread and the breadth (spec §6.17, P42)",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"baselines", "application/json", %Schema{type: :array}}]
  )

  def baselines(conn, %{"id" => id}),
    do:
      json(
        conn,
        id
        |> Ethos.baselines()
        |> Enum.map(&%{at: &1.at, habits: &1.habits, spread: &1.spread, breadth: &1.breadth})
      )

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
            :agathos_daimon_web_character_not_witnessed
          )
        )
        |> halt()
  end

  defp habit(h) do
    %{
      number: h.number,
      name: h.name,
      trigger: h.trigger,
      stance: h.stance,
      seed_number: h.seed_number,
      habit: h.habit,
      connection: h.connection,
      citations: h.citations,
      days: h.days,
      affirmations: h.affirmations,
      defined_by: %{kind: h.defined_by_kind, id: h.defined_by_id},
      defined_at: h.defined_at,
      revised_at: h.revised_at,
      revisions: h.revisions
    }
  end

  defp commitment(c) do
    %{
      number: c.number,
      to: c.to,
      text: c.text,
      state: c.state,
      made_at: c.made_at,
      closed_at: c.closed_at,
      closed_by_kind: c.closed_by_kind,
      note: c.note
    }
  end

  defp seed(s) do
    %{
      number: s.number,
      text: s.text,
      state: s.state,
      planted_at: s.planted_at,
      closed_at: s.closed_at,
      graduated_to: s.graduated_to_kind && %{kind: s.graduated_to_kind, id: s.graduated_to_id},
      graduation_note: s.graduation_note,
      citations: s.citations,
      days: s.days
    }
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [:ethos_no_such_habit, :ethos_no_such_commitment],
       do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)

  defp respond(conn, {:error, reason}),
    do: problem(conn, 422, :refused, :web_character_respond_refused, inspect(reason))

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _other -> 0
    end
  end
end
