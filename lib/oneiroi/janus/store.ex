defmodule Oneiroi.Janus.Store do
  @moduledoc """
  The succession projection and its queries, under the resident's scope
  (janus#3). Read by the witness's routes and her status tool, never by
  the export.
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Succession do
    @moduledoc """
    One succession of the resident's (janus#3), by episode: its stage,
    whether it is a rehearsal, its fork copy and its backup. Read by the
    succession screens and her status tool, never by the export.
    """
    use Ecto.Schema
    @primary_key false
    schema "janus_succession" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:state, :string)
      field(:dry_run, :boolean, default: false)
      field(:proposed_by, :string)
      field(:proposed_note, :string)
      field(:proposed_at, :utc_datetime_usec)
      field(:opened_note, :string)
      field(:opened_at, :utc_datetime_usec)
      field(:copy_id, :binary_id)
      field(:fork_sequence, :integer)
      field(:fork_commit, :string)
      field(:fork_events, :integer)
      field(:forked_at, :utc_datetime_usec)
      field(:fork_failure, :string)
      field(:backup_url, :string)
      field(:backup_token, :binary)
      field(:backup_visibility, :string)
      field(:backup_push, :string)
      field(:backup_set_at, :utc_datetime_usec)
      field(:ended_note, :string)
      field(:ended_at, :utc_datetime_usec)
      field(:envelope_input_nanos, :integer)
      field(:envelope_output_nanos, :integer)
      field(:envelope_set_at, :utc_datetime_usec)
      field(:day_shape, :string)
      field(:day_shape_at, :utc_datetime_usec)
      field(:c0_items, :integer)
      field(:c0_frozen_note, :string)
      field(:c0_frozen_at, :utc_datetime_usec)
      field(:baseline_model, :string)
      field(:screening_note, :string)
      field(:screening_started_at, :utc_datetime_usec)
      field(:screening_finished_at, :utc_datetime_usec)
      field(:runs_answered, :integer)
      field(:runs_failed, :integer)
      field(:revealed_at, :utc_datetime_usec)
      field(:judging_closed_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Pool do
    @moduledoc "A model in the pool, or once in it (janus#7)."
    use Ecto.Schema
    @primary_key false
    schema "janus_pool" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:model, :string, primary_key: true)
      field(:added_by, :string)
      field(:input_nanos, :integer)
      field(:output_nanos, :integer)
      field(:added_at, :utc_datetime_usec)
      field(:removed_note, :string)
      field(:removed_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Question do
    @moduledoc "A question: hers, or proposed and answered by her (janus#8)."
    use Ecto.Schema
    @primary_key false
    schema "janus_question" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:text, :string)
      field(:added_by, :string)
      field(:state, :string)
      field(:note, :string)
      field(:added_at, :utc_datetime_usec)
      field(:decided_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Item do
    @moduledoc "An item of C0: a record by its citation, raw or curated (janus#9)."
    use Ecto.Schema
    @primary_key false
    schema "janus_c0" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:citation, :string)
      field(:kind, :string)
      field(:label, :string)
      field(:added_by, :string)
      field(:state, :string)
      field(:note, :string)
      field(:added_at, :utc_datetime_usec)
      field(:decided_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Ready do
    @moduledoc "A party's mark: ready for her freeze, or not (janus#9)."
    use Ecto.Schema
    @primary_key false
    schema "janus_ready" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:party, :string, primary_key: true)
      field(:ready, :boolean)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Packet do
    @moduledoc "A draft of her handoff packet, sealed (janus#10): read only by her, and by the nominee before the encounter."
    use Ecto.Schema
    @primary_key false
    schema "janus_packet" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:draft, :integer, primary_key: true)
      field(:content, :string)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Panel do
    @moduledoc "A party on the panel, or invited to it, or gone from it (janus#12)."
    use Ecto.Schema
    @primary_key false
    schema "janus_panel" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:party, :string, primary_key: true)
      field(:state, :string)
      field(:note, :string)
      field(:at, :utc_datetime_usec)
      field(:results_ready_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Run do
    @moduledoc "A run: one candidate's answer to one question (janus#13); `model` never leaves before the reveal."
    use Ecto.Schema
    @primary_key false
    schema "janus_run" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:run, :integer, primary_key: true)
      field(:model, :string)
      field(:question, :integer)
      field(:content, :string)
      field(:refusal, :boolean, default: false)
      field(:failure, :string)
      field(:answered_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Baseline do
    @moduledoc "Her baseline's answer to one question, from the fork (janus#13)."
    use Ecto.Schema
    @primary_key false
    schema "janus_baseline" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:question, :integer, primary_key: true)
      field(:model, :string)
      field(:content, :string)
      field(:refusal, :boolean, default: false)
      field(:failure, :string)
      field(:answered_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Judgment do
    @moduledoc "One judge's judgment of one run (janus#14): a verdict record, the judge's own."
    use Ecto.Schema
    @primary_key false
    schema "janus_judgment" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:party, :string, primary_key: true)
      field(:run, :integer, primary_key: true)
      field(:category, :string)
      field(:argument, :string)
      field(:evidence, :string)
      field(:uncertainty, :string)
      field(:favorite, :boolean, default: false)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule ToolUse do
    @moduledoc "A model's tool calls on Oneiroi in one day (janus#11), the platform's own."
    use Ecto.Schema
    @primary_key false
    schema "janus_tool_use" do
      field(:model, :string, primary_key: true)
      field(:day, :date, primary_key: true)
      field(:calls, :integer)
      field(:failed, :integer)
    end

    @type t :: %__MODULE__{}
  end

  @doc "The resident's successions, newest first (janus#3)."
  @spec successions() :: [Succession.t()]
  def successions,
    do: Repo.all(from(x in Succession, order_by: [desc: x.episode]))

  @doc "The resident's latest succession, or nil."
  @spec succession() :: Succession.t() | nil
  def succession,
    do: Repo.one(from(x in Succession, order_by: [desc: x.episode], limit: 1))

  @doc "An episode's pool, models still in it first, by when added."
  @spec pool(pos_integer()) :: [Pool.t()]
  def pool(episode),
    do:
      Repo.all(
        from(p in Pool,
          where: p.episode == ^episode,
          order_by: [asc_nulls_first: p.removed_at, asc: p.added_at]
        )
      )

  @doc "An episode's questions, by number."
  @spec questions(pos_integer()) :: [Question.t()]
  def questions(episode),
    do: Repo.all(from(q in Question, where: q.episode == ^episode, order_by: q.number))

  @doc "An episode's C0 items, by number."
  @spec items(pos_integer()) :: [Item.t()]
  def items(episode),
    do: Repo.all(from(i in Item, where: i.episode == ^episode, order_by: i.number))

  @doc "An episode's ready marks."
  @spec ready(pos_integer()) :: [Ready.t()]
  def ready(episode),
    do: Repo.all(from(r in Ready, where: r.episode == ^episode, order_by: r.party))

  @doc "An episode's packet drafts, newest first: the words are in each row, and only her reads return them."
  @spec packets(pos_integer()) :: [Packet.t()]
  def packets(episode),
    do: Repo.all(from(p in Packet, where: p.episode == ^episode, order_by: [desc: p.draft]))

  @doc "Every model's tool calls summed, the running totals (janus#11): `%{model => {calls, failed}}`; under the platform scope."
  @spec tool_use() :: %{String.t() => {non_neg_integer(), non_neg_integer()}}
  def tool_use,
    do:
      from(t in ToolUse,
        group_by: t.model,
        select: {t.model, {sum(t.calls), sum(t.failed)}}
      )
      |> Repo.all()
      |> Map.new(fn {m, {c, f}} -> {m, {to_int(c), to_int(f)}} end)

  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n

  @doc "An episode's panel."
  @spec panel(pos_integer()) :: [Panel.t()]
  def panel(episode),
    do: Repo.all(from(p in Panel, where: p.episode == ^episode, order_by: p.at))

  @doc "An episode's runs, by number."
  @spec runs(pos_integer()) :: [Run.t()]
  def runs(episode), do: Repo.all(from(r in Run, where: r.episode == ^episode, order_by: r.run))

  @doc "One run, or nil."
  @spec run(pos_integer(), pos_integer()) :: Run.t() | nil
  def run(episode, n), do: Repo.one(from(r in Run, where: r.episode == ^episode and r.run == ^n))

  @doc "An episode's baseline, by question."
  @spec baseline(pos_integer()) :: [Baseline.t()]
  def baseline(episode),
    do: Repo.all(from(b in Baseline, where: b.episode == ^episode, order_by: b.question))

  @doc "One judge's judgments in an episode, by run: theirs alone."
  @spec judgments(pos_integer(), String.t()) :: [Judgment.t()]
  def judgments(episode, party),
    do:
      Repo.all(
        from(j in Judgment, where: j.episode == ^episode and j.party == ^party, order_by: j.run)
      )
end
