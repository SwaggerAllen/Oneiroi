defmodule OneiroiWeb.FigureController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.HuginnMuninn
  alias OpenApiSpex.Schema

  tags(["audits"])

  plug(:witnessed)

  operation(:figures,
    summary:
      "Every figure, fresh: counters as the fold of their increments, countdowns derived from dates",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"figures", "application/json", %Schema{type: :array}}]
  )

  def figures(conn, %{"id" => id}), do: json(conn, HuginnMuninn.figures(id))

  operation(:figure,
    summary: "One figure with, for a counter, its latest increments and their actors",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    responses: [ok: {"the figure", "application/json", %Schema{type: :object}}]
  )

  def figure(conn, %{"id" => id, "key" => key}) do
    case HuginnMuninn.figure(id, key) do
      nil ->
        error(conn, 404, HuginnMuninn.Error.new(:huginn_muninn_no_such_figure, key: key))

      %{kind: "counter"} = f ->
        increments = id |> HuginnMuninn.increments(key, 50) |> Enum.map(&increment/1)
        json(conn, Map.put(f, :recent, increments))

      f ->
        json(conn, f)
    end
  end

  operation(:define_counter,
    summary: "Define a counter: a key and a label",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the counter", "application/json",
       %Schema{
         type: :object,
         required: [:key, :label],
         properties: %{key: %Schema{type: :string}, label: %Schema{type: :string}}
       }},
    responses: [no_content: "defined"]
  )

  def define_counter(conn, %{"id" => id} = params),
    do:
      respond(conn, HuginnMuninn.define_counter(id, params["key"], params["label"], actor(conn)))

  operation(:increment,
    summary: "Increment a counter, with a note; negative corrects",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    request_body:
      {"the increment", "application/json",
       %Schema{
         type: :object,
         properties: %{by: %Schema{type: :integer, default: 1}, note: %Schema{type: :string}}
       }},
    responses: [no_content: "incremented"]
  )

  def increment(conn, %{"id" => id, "key" => key} = params),
    do:
      respond(
        conn,
        HuginnMuninn.increment(id, key, integer(params["by"]) || 1, params["note"], actor(conn))
      )

  operation(:retire_counter,
    summary: "Retire a counter",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    responses: [no_content: "retired"]
  )

  def retire_counter(conn, %{"id" => id, "key" => key}),
    do: respond(conn, HuginnMuninn.retire_counter(id, key, actor(conn)))

  operation(:light,
    summary: "The check-engine light: its state, the findings that count, every latest result",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the light", "application/json", %Schema{type: :object}}]
  )

  def light(conn, %{"id" => id}), do: json(conn, HuginnMuninn.light(id))

  operation(:checks,
    summary: "Every audit, built-in and the witness's, with its last result",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"audits", "application/json", %Schema{type: :array}}]
  )

  def checks(conn, %{"id" => id}),
    do: json(conn, id |> HuginnMuninn.audits() |> Enum.map(&check/1))

  operation(:define_check,
    summary:
      "Define an audit: a rule over a figure (figure op value), a tone when it fails, whether it counts toward the light",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the audit", "application/json",
       %Schema{
         type: :object,
         required: [:key, :label, :figure, :op, :value],
         properties: %{
           key: %Schema{type: :string},
           label: %Schema{type: :string},
           figure: %Schema{type: :string},
           op: %Schema{type: :string, enum: ~w(>= <= == > <)},
           value: %Schema{type: :integer},
           tone: %Schema{type: :string, enum: ~w(warn fail), default: "warn"},
           counts: %Schema{type: :boolean, default: true}
         }
       }},
    responses: [no_content: "defined"]
  )

  def define_check(conn, %{"id" => id} = params) do
    attrs = %{
      key: params["key"],
      label: params["label"],
      figure: params["figure"],
      op: params["op"],
      value: integer(params["value"]),
      tone: params["tone"] || "warn",
      counts: Map.get(params, "counts", true) == true
    }

    respond(conn, HuginnMuninn.define_audit(id, attrs, actor(conn)))
  end

  operation(:retire_check,
    summary: "Retire an audit of the witness's",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    responses: [no_content: "retired"]
  )

  def retire_check(conn, %{"id" => id, "key" => key}),
    do: respond(conn, HuginnMuninn.retire_audit(id, key, actor(conn)))

  operation(:run_checks,
    summary: "Run every audit now; returns the light",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the light", "application/json", %Schema{type: :object}}]
  )

  def run_checks(conn, %{"id" => id}) do
    case HuginnMuninn.run_audits(id, actor(conn)) do
      {:ok, light} -> json(conn, light)
      other -> respond(conn, other)
    end
  end

  # ---- shapes ----

  defp increment(i),
    do: %{at: i.at, by: i.by, note: i.note, actor: %{kind: i.actor_kind, id: i.actor_id}}

  defp check(a) do
    last =
      a.last && %{tone: a.last.tone, value: a.last.value, finding: a.last.finding, at: a.last.at}

    a |> Map.drop([:last]) |> Map.put(:last, last)
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
            :agathos_daimon_web_figure_not_witnessed
          )
        )
        |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [:huginn_muninn_no_such_figure, :huginn_muninn_no_such_audit],
       do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)

  defp respond(conn, {:error, reason}),
    do: problem(conn, 422, :refused, :web_figure_respond_refused, inspect(reason))

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp integer(_other), do: nil
end
