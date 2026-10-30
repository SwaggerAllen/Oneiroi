defmodule Oneiroi.Ethos.Store do
  @moduledoc "The character layer's projections and queries, under the resident's scope."
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Seed do
    @moduledoc "A becoming (spec §6.17, P37): the resident's words, its state, and what it graduated to."
    use Ecto.Schema
    @primary_key false
    schema "ethos_seed" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:text, :string)
      field(:state, :string, default: "open")
      field(:planted_at, :utc_datetime_usec)
      field(:closed_at, :utc_datetime_usec)
      field(:graduated_to_kind, :string)
      field(:graduated_to_id, :string)
      field(:graduation_note, :string)
      field(:citations, :integer, virtual: true, default: 0)
      field(:days, :integer, virtual: true, default: 0)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Habit do
    @moduledoc "How the resident tends to act (spec §6.17, P38): its words, the trigger, the stance, as last revised, with its scores computed on read."
    use Ecto.Schema
    @primary_key false
    schema "ethos_habit" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:name, :string)
      field(:trigger, :map, default: %{})
      field(:stance, :string)
      field(:seed_number, :integer)
      field(:defined_by_kind, :string)
      field(:defined_by_id, :string)
      field(:defined_at, :utc_datetime_usec)
      field(:revised_at, :utc_datetime_usec)
      field(:revisions, :integer, default: 0)
      field(:habit, :float, virtual: true, default: 0.0)
      field(:connection, :float, virtual: true, default: 0.0)
      field(:affirmations, :integer, virtual: true, default: 0)
      field(:citations, :integer, virtual: true, default: 0)
      field(:days, :integer, virtual: true, default: 0)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Citation do
    @moduledoc "One citation from a seed or a habit to the moment that evidenced it."
    use Ecto.Schema
    @primary_key false
    schema "ethos_citation" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:kind, :string, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:target_kind, :string, primary_key: true)
      field(:target_id, :string, primary_key: true)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Affirmation do
    @moduledoc "One affirmation of a habit by the witness, with its note."
    use Ecto.Schema
    @primary_key false
    schema "ethos_affirmation" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:at, :utc_datetime_usec, primary_key: true)
      field(:note, :string)
      field(:by_kind, :string)
      field(:by_id, :string)
    end

    @type t :: %__MODULE__{}
  end

  @doc "Every seed, by number."
  @spec seeds() :: [Seed.t()]
  def seeds, do: Repo.all(from(s in Seed, order_by: s.number))

  @doc "Every habit, by number."
  @spec habits() :: [Habit.t()]
  def habits, do: Repo.all(from(h in Habit, order_by: h.number))

  @doc "Every citation of one kind, newest first."
  @spec citations(String.t()) :: [Citation.t()]
  def citations(kind),
    do: Repo.all(from(c in Citation, where: c.kind == ^kind, order_by: [desc: c.at]))

  @doc "Every affirmation, newest first."
  @spec affirmations() :: [Affirmation.t()]
  def affirmations, do: Repo.all(from(a in Affirmation, order_by: [desc: a.at]))
end
