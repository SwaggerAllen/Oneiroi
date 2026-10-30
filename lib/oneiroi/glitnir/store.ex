defmodule Oneiroi.Glitnir.Store do
  @moduledoc "The governance projections and their queries, under the resident's scope."
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Report do
    @moduledoc "A report: who filed it, its text, its state and resolution."
    use Ecto.Schema
    @primary_key false
    schema "glitnir_report" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:by_kind, :string)
      field(:by_id, :string)
      field(:text, :string)
      field(:filed_at, :utc_datetime_usec)
      field(:state, :string)
      field(:outcome, :string)
      field(:resolved_at, :utc_datetime_usec)
      field(:resolution_note, :string)
      field(:resolved_by_id, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Step do
    @moduledoc "One investigation step on a report, with its reason and the investigator."
    use Ecto.Schema
    @primary_key false
    schema "glitnir_step" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:sequence, :integer, primary_key: true)
      field(:at, :utc_datetime_usec)
      field(:reason, :string)
      field(:by_id, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Strike do
    @moduledoc "A strike on the human, with its consequence."
    use Ecto.Schema
    @primary_key false
    schema "glitnir_strike" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:report, :integer)
      field(:witness_account_id, :binary_id)
      field(:consequence, :string)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  def reports, do: Repo.all(from(r in Report, order_by: [desc: r.number]))
  def report(number), do: Repo.one(from(r in Report, where: r.number == ^number))

  def steps(number),
    do: Repo.all(from(s in Step, where: s.number == ^number, order_by: s.sequence))

  def steps_of(numbers) when is_list(numbers),
    do: Repo.all(from(s in Step, where: s.number in ^numbers, order_by: [s.number, s.sequence]))

  def strikes, do: Repo.all(from(s in Strike, order_by: s.number))
end
