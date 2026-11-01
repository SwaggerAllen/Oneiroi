defmodule OneiroiWeb.RegressionController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Eunomia
  alias OpenApiSpex.Schema

  tags(["regression"])

  plug(:witnessed)

  # A module attribute rather than a function: `operation` runs at
  # compile time, before any function of this module exists.
  @test_schema %Schema{
    type: :object,
    required: [:prompt, :passes_if, :fails_if],
    properties: %{
      prompt: %Schema{type: :string},
      passes_if: %Schema{type: :string},
      fails_if: %Schema{type: :string}
    }
  }

  operation(:tests,
    summary: "The regression tests: prompt, passes if, fails if",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"tests", "application/json", %Schema{type: :array}}]
  )

  def tests(conn, %{"id" => id}), do: json(conn, id |> Eunomia.tests() |> Enum.map(&test/1))

  operation(:write_test,
    summary: "Write a test: three texts",
    parameters: [id: [in: :path, type: :string]],
    request_body: {"the test", "application/json", @test_schema},
    responses: [created: {"the number", "application/json", %Schema{type: :object}}]
  )

  def write_test(conn, %{"id" => id, "prompt" => p, "passes_if" => y, "fails_if" => n}) do
    case Eunomia.write_test(id, %{prompt: p, passes_if: y, fails_if: n}, actor(conn)) do
      {:ok, number} -> conn |> put_status(201) |> json(%{number: number})
      other -> respond(conn, other)
    end
  end

  def write_test(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_regression_write_test_fields_required,
        "prompt, passes_if and fails_if are required"
      )

  operation(:change_test,
    summary: "Change a test's three texts",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body: {"the test", "application/json", @test_schema},
    responses: [no_content: "changed"]
  )

  def change_test(conn, %{
        "id" => id,
        "number" => number,
        "prompt" => p,
        "passes_if" => y,
        "fails_if" => n
      }) do
    respond(
      conn,
      Eunomia.change_test(
        id,
        integer(number),
        %{prompt: p, passes_if: y, fails_if: n},
        actor(conn)
      )
    )
  end

  def change_test(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_regression_change_test_fields_required,
        "prompt, passes_if and fails_if are required"
      )

  operation(:runs,
    summary: "The runs, newest first",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"runs", "application/json", %Schema{type: :array}}]
  )

  def runs(conn, %{"id" => id}), do: json(conn, id |> Eunomia.runs() |> Enum.map(&run/1))

  operation(:start_run,
    summary:
      "Run candidate models against the tests (all, or the numbers given), in sealed sessions; returns the run",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the run", "application/json",
       %Schema{
         type: :object,
         required: [:models],
         properties: %{
           models: %Schema{type: :array, items: %Schema{type: :string}},
           tests: %Schema{type: :array, items: %Schema{type: :integer}},
           behaviours: %Schema{
             description: "behaviour numbers to derive trials from, or \"all\"",
             oneOf: [
               %Schema{type: :array, items: %Schema{type: :integer}},
               %Schema{type: :string, enum: ["all"]}
             ]
           }
         }
       }},
    responses: [created: {"the run's ref", "application/json", %Schema{type: :object}}]
  )

  def start_run(conn, %{"id" => id, "models" => models} = params) when is_list(models) do
    tests = if is_list(params["tests"]), do: Enum.map(params["tests"], &integer/1), else: :all

    selection = %{
      tests: tests,
      behaviours: numbers_or_all(params["behaviours"]),
      commitments: numbers_or_all(params["commitments"])
    }

    case Eunomia.run(id, models, selection, actor(conn)) do
      {:ok, ref} -> conn |> put_status(201) |> json(%{ref: ref})
      other -> respond(conn, other)
    end
  end

  def start_run(conn, _params),
    do:
      problem(
        conn,
        422,
        :models_required,
        :web_regression_start_run_models_required,
        "models is required"
      )

  # "all", a list of numbers, or nothing.
  defp numbers_or_all("all"), do: :all
  defp numbers_or_all(list) when is_list(list), do: Enum.map(list, &integer/1)
  defp numbers_or_all(_none), do: []

  operation(:run,
    summary: "A run with its cards, blind until a test's cards are all graded, and its results",
    parameters: [id: [in: :path, type: :string], ref: [in: :path, type: :string]],
    responses: [ok: {"the run", "application/json", %Schema{type: :object}}]
  )

  def run(conn, %{"id" => id, "ref" => ref}) do
    case Eunomia.run_detail(id, ref) do
      {:ok, r, cards, results} -> json(conn, %{run: run(r), cards: cards, results: results})
      other -> respond(conn, other)
    end
  end

  operation(:grade,
    summary: "Grade a card pass or fail",
    parameters: [
      id: [in: :path, type: :string],
      ref: [in: :path, type: :string],
      card: [in: :path, type: :string]
    ],
    request_body:
      {"the grade", "application/json",
       %Schema{
         type: :object,
         required: [:grade],
         properties: %{grade: %Schema{type: :string, enum: ["pass", "fail"]}}
       }},
    responses: [no_content: "graded"]
  )

  def grade(conn, %{"id" => id, "ref" => ref, "card" => card, "grade" => grade}),
    do: respond(conn, Eunomia.grade(id, ref, card, grade, actor(conn)))

  def grade(conn, _params),
    do:
      problem(
        conn,
        422,
        :grade_required,
        :web_regression_grade_grade_required,
        "grade is required"
      )

  operation(:favourite,
    summary: "Favourite a card",
    parameters: [
      id: [in: :path, type: :string],
      ref: [in: :path, type: :string],
      card: [in: :path, type: :string]
    ],
    responses: [no_content: "favourited"]
  )

  def favourite(conn, %{"id" => id, "ref" => ref, "card" => card}),
    do: respond(conn, Eunomia.favourite(id, ref, card, actor(conn)))

  operation(:pin_model,
    summary: "Pin the chat model: a regression favourite (reason run) or the witness's choice",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the pin", "application/json",
       %Schema{
         type: :object,
         required: [:model],
         properties: %{
           model: %Schema{type: :string},
           reason: %Schema{type: :string, enum: ["run", "witness"]}
         }
       }},
    responses: [no_content: "pinned"]
  )

  def pin_model(conn, %{"id" => id, "model" => model} = params) do
    respond(
      conn,
      Oneiroi.AgathosDaimon.pin_model(
        id,
        model,
        Map.get(params, "reason", "witness"),
        actor(conn)
      )
    )
  end

  def pin_model(conn, _params),
    do:
      problem(
        conn,
        422,
        :model_required,
        :web_regression_pin_model_model_required,
        "model is required"
      )

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else: conn |> error(404, ResidentError.new(:agathos_daimon_not_witnessed)) |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [:eunomia_no_such_test, :eunomia_no_such_run, :eunomia_no_such_card],
       do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)

  defp respond(conn, {:error, reason}),
    do: problem(conn, 422, :refused, :web_regression_respond_refused, inspect(reason))

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> 0
    end
  end

  defp test(t),
    do: %{
      number: t.number,
      prompt: t.prompt,
      passes_if: t.passes_if,
      fails_if: t.fails_if,
      written_at: t.written_at,
      changed_at: t.changed_at
    }

  defp run(r),
    do: %{
      ref: r.ref,
      models: r.models,
      tests: r.tests,
      started_at: r.started_at,
      finished_at: r.finished_at,
      cards: r.cards
    }
end
