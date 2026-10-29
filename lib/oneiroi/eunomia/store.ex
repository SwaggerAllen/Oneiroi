defmodule Oneiroi.Eunomia.Store do
  @moduledoc """
  The regression projections and their queries, under the resident's
  scope and read only by the steward's routes: no tool, no export and no
  other system reads them (spec §6.4's unawareness invariant).
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Test do
    @moduledoc "A test: three texts, as last changed."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_regression_test" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:prompt, :string)
      field(:passes_if, :string)
      field(:fails_if, :string)
      field(:written_at, :utc_datetime_usec)
      field(:changed_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Run do
    @moduledoc "A run of models x tests, with its progress."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_regression_run" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:ref, :string, primary_key: true)
      field(:models, {:array, :string}, default: [])
      field(:tests, {:array, :integer}, default: [])
      field(:started_at, :utc_datetime_usec)
      field(:finished_at, :utc_datetime_usec)
      field(:cards, :integer, default: 0)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Answer do
    @moduledoc "One card: a model's answer to a test, graded blind, the model shown once every card of the test is graded."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_regression_answer" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:run_ref, :string, primary_key: true)
      field(:card_ref, :string, primary_key: true)
      field(:model, :string)
      field(:test_number, :integer)
      field(:content, :string)
      field(:refusal, :boolean, default: false)
      field(:failure, :string)
      field(:grade, :string)
      field(:favourite, :boolean, default: false)
      field(:recorded_at, :utc_datetime_usec)
      field(:graded_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @spec tests() :: [Test.t()]
  def tests, do: Repo.all(from(t in Test, order_by: t.number))

  @spec test(pos_integer()) :: Test.t() | nil
  def test(number), do: Repo.one(from(t in Test, where: t.number == ^number))

  @spec runs() :: [Run.t()]
  def runs, do: Repo.all(from(r in Run, order_by: [desc: r.started_at]))

  @spec run(String.t()) :: Run.t() | nil
  def run(ref), do: Repo.one(from(r in Run, where: r.ref == ^ref))

  @doc "A run's cards in a fixed order: by test, then by card ref, so the grader's deck is stable and says nothing of the model."
  @spec answers(String.t()) :: [Answer.t()]
  def answers(run_ref),
    do:
      Repo.all(
        from(a in Answer,
          where: a.run_ref == ^run_ref,
          order_by: [asc: a.test_number, asc: a.card_ref]
        )
      )
end
