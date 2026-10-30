defmodule Oneiroi.Eunomia.Store do
  @moduledoc """
  The judgement and regression projections and their queries, under the
  resident's scope. The regression rows are read only by the witness's
  routes: no tool, no export and no other system reads them (spec §6.4's
  unawareness invariant). The judgement rows are the resident's record
  and the brain's tools read them.
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
      field(:behaviours, {:array, :integer}, default: [])
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
      field(:behaviour_number, :integer)
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

  defmodule Position do
    @moduledoc "A position the resident holds, with its place in a chain."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_position" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:statement, :string)
      field(:session_key, :string)
      field(:turn_ref, :string)
      field(:replaces, :integer)
      field(:replaced_by, :integer)
      field(:taken_at, :utc_datetime_usec)
      field(:replaced_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Dispute do
    @moduledoc "A dispute, live or nightly: the check with the judge's advice and model, and its settlement."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_dispute" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:ref, :string, primary_key: true)
      field(:source, :string)
      field(:position_number, :integer)
      field(:claim, :string)
      field(:stance, :string)
      field(:session_key, :string)
      field(:turn_ref, :string)
      field(:outcome, :string)
      field(:advice, :string)
      field(:advice_text, :string)
      field(:judge_model, :string)
      field(:criteria, :string)
      field(:checked_at, :utc_datetime_usec)
      field(:settlement, :string)
      field(:settled_note, :string)
      field(:settled_by_kind, :string)
      field(:settled_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Prediction do
    @moduledoc "A prediction with its due instant, resolved by the witness."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_prediction" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:statement, :string)
      field(:due, :utc_datetime_usec)
      field(:session_key, :string)
      field(:turn_ref, :string)
      field(:logged_at, :utc_datetime_usec)
      field(:outcome, :string)
      field(:note, :string)
      field(:resolved_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Night do
    @moduledoc "One nightly pass: judged or failed, how much was read, what was found."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_night" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:day, :string, primary_key: true)
      field(:at, :utc_datetime_usec, primary_key: true)
      field(:outcome, :string)
      field(:messages, :integer)
      field(:chars, :integer)
      field(:found, :integer)
      field(:judge_model, :string)
      field(:criteria, :string)
      field(:summary, :string)
      field(:reason, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule JudgeChange do
    @moduledoc "A change of the judge's model, so the ratio chart marks it."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_judge_change" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:at, :utc_datetime_usec, primary_key: true)
      field(:model, :string)
      field(:previous, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Audit do
    @moduledoc "One weekly memory audit: what the judge read and flagged, or why it failed."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_audit" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:ref, :string, primary_key: true)
      field(:outcome, :string)
      field(:conclusions, :integer)
      field(:flagged, :integer)
      field(:judge_model, :string)
      field(:criteria, :string)
      field(:summary, :string)
      field(:reason, :string)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule AuditFlag do
    @moduledoc "A conclusion the judge flagged, awaiting the witness: approved (the conclusion goes) or deleted (it stays), with a note."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_audit_flag" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:ref, :string, primary_key: true)
      field(:audit_ref, :string)
      field(:conclusion_id, :string)
      field(:conclusion, :string)
      field(:reason, :string)
      field(:raised_at, :utc_datetime_usec)
      field(:decision, :string)
      field(:note, :string)
      field(:decided_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @spec audits() :: [Audit.t()]
  def audits, do: Repo.all(from(a in Audit, order_by: [desc: a.at]))

  defmodule Wash do
    @moduledoc "One wash pass (spec §6.13, P18): the entries read, the flags raised, the model, the outcome."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_wash" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:ref, :string, primary_key: true)
      field(:outcome, :string)
      field(:entries, :integer)
      field(:flagged, :integer)
      field(:judge_model, :string)
      field(:criteria, :string)
      field(:summary, :string)
      field(:reason, :string)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule WashFlag do
    @moduledoc "One entry the wash pass flagged, with its kind, and the resident's decision when made."
    use Ecto.Schema
    @primary_key false
    schema "eunomia_wash_flag" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:ref, :string, primary_key: true)
      field(:wash_ref, :string)
      field(:file, :string)
      field(:entry, :string)
      field(:kind, :string)
      field(:reason, :string)
      field(:raised_at, :utc_datetime_usec)
      field(:decision, :string)
      field(:note, :string)
      field(:decided_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @spec washes() :: [Wash.t()]
  def washes, do: Repo.all(from(w in Wash, order_by: [desc: w.at]))

  @spec wash_flags() :: [WashFlag.t()]
  def wash_flags, do: Repo.all(from(f in WashFlag, order_by: [asc: f.raised_at, asc: f.ref]))

  @spec audit_flags() :: [AuditFlag.t()]
  def audit_flags, do: Repo.all(from(f in AuditFlag, order_by: [asc: f.raised_at, asc: f.ref]))

  @spec positions() :: [Position.t()]
  def positions, do: Repo.all(from(p in Position, order_by: p.number))

  @spec position(pos_integer()) :: Position.t() | nil
  def position(number), do: Repo.one(from(p in Position, where: p.number == ^number))

  @spec disputes() :: [Dispute.t()]
  def disputes, do: Repo.all(from(d in Dispute, order_by: [desc: d.checked_at]))

  @spec dispute(String.t()) :: Dispute.t() | nil
  def dispute(ref), do: Repo.one(from(d in Dispute, where: d.ref == ^ref))

  @spec predictions() :: [Prediction.t()]
  def predictions, do: Repo.all(from(p in Prediction, order_by: [asc: p.due, asc: p.number]))

  @spec nights() :: [Night.t()]
  def nights, do: Repo.all(from(n in Night, order_by: [desc: n.day, desc: n.at]))

  @spec judge_changes() :: [JudgeChange.t()]
  def judge_changes, do: Repo.all(from(j in JudgeChange, order_by: j.at))

  @doc "The judge's model as last chosen, or nil for the platform's."
  @spec judge_model() :: String.t() | nil
  def judge_model do
    Repo.one(from(j in JudgeChange, order_by: [desc: j.at], limit: 1, select: j.model))
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
          order_by: [asc: a.test_number, asc: a.behaviour_number, asc: a.card_ref]
        )
      )
end
