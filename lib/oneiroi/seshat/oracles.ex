defmodule Oneiroi.Seshat.Oracles do
  @moduledoc """
  The oracle's records (brain #49, seshat #34): questions dispatched,
  answers written under oracle/ by the platform on the resident's
  behalf, failures said as failures. The run itself is the brain's
  (`Oneiroi.Brain.Oracle`); this is the library's half: the stream, the
  document and the deliberate query.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Router
  alias Oneiroi.Seshat.Store

  @doc "Dispatches named questions, each `%{question, sources}`; returns their numbers, in order."
  def dispatch(resident_id, session_key, questions, %Actor{} = actor) do
    command = %Commands.DispatchOracle{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      session_key: session_key,
      questions: Enum.map(List.wrap(questions), &question/1)
    }

    with {:ok, events} <- dispatch(command), do: {:ok, Enum.map(events, & &1.number)}
  end

  @doc """
  Writes the answer to question `number` at oracle/<number>-<slug>.md,
  attributed to `actor` (the resident, with the model that read), then
  records it answered; returns the path.
  """
  def answer(resident_id, number, content, %{} = measured, %Actor{} = actor) do
    with %Store.Oracle{} = row <- oracle(resident_id, number) || absent(number),
         path = "oracle/#{number}-#{slug(row.question)}.md",
         {:ok, _written} <- Documents.write(resident_id, path, content, actor, core: true),
         {:ok, _events} <-
           dispatch(%Commands.AnswerOracle{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             number: number,
             path: path,
             confidence: measured[:confidence],
             read: measured[:read] || [],
             used: measured[:used] || []
           }) do
      {:ok, path}
    end
  end

  @doc "Records question `number` as failed, with the reason in words."
  def fail(resident_id, number, reason, %Actor{} = actor) do
    command = %Commands.FailOracle{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      reason: reason
    }

    with {:ok, _events} <- dispatch(command), do: :ok
  end

  @doc "The oracle's questions, newest first, narrowed by `source:`, `read:`, `used:`, `status:`, `asked_by:`, `q:`, `limit:`."
  def oracles(resident_id, opts \\ []),
    do: Scope.resident(resident_id, fn -> Store.oracles(opts) end)

  @doc "One question by number, or nil."
  def oracle(resident_id, number), do: Scope.resident(resident_id, fn -> Store.oracle(number) end)

  defp question(%{} = q) do
    %{
      question: to_string(Map.get(q, :question) || Map.get(q, "question") || ""),
      sources:
        q |> Map.get(:sources, Map.get(q, "sources")) |> List.wrap() |> Enum.map(&to_string/1)
    }
  end

  defp question(_other), do: %{question: "", sources: []}

  defp absent(number),
    do: {:error, Error.new(:seshat_no_such_oracle, :seshat_oracles_answer_absent, number: number)}

  # A filename from the question's first words: lower case, letters and
  # digits joined by `-`, at most six words; the number keeps it unique.
  defp slug(question) do
    question
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.split()
    |> Enum.take(6)
    |> Enum.join("-")
    |> case do
      "" -> "question"
      slug -> slug
    end
  end

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:seshat_dispatch_failed, :seshat_oracles_dispatch_failed, reason)}
    end
  end
end
