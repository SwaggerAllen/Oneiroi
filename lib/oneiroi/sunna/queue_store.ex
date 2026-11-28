defmodule Oneiroi.Sunna.QueueStore do
  @moduledoc "The house queue's projection rows (sunna#80), platform-scoped: the household's, every member's."

  defmodule Project do
    @moduledoc "A project of the house queue: a name, a slug, an owner, open or closed."
    use Ecto.Schema
    @primary_key false
    schema "sunna_queue_project" do
      field(:household_id, :binary_id, primary_key: true)
      field(:slug, :string, primary_key: true)
      field(:name, :string)
      field(:owner, :string)
      field(:status, :string)
      field(:opened_at, :utc_datetime_usec)
      field(:closed_at, :utc_datetime_usec)
      field(:note, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Task do
    @moduledoc "A task: its outcome, owner and index document; `status` open, complete or dropped, and its open layer."
    use Ecto.Schema
    @primary_key false
    schema "sunna_queue_task" do
      field(:household_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:project, :string)
      field(:slug, :string)
      field(:title, :string)
      field(:outcome, :string)
      field(:owner, :string)
      field(:index_doc, :string)
      field(:template, :string)
      # The template's version it was opened from, and whether its layers
      # have been edited since (sunna#90).
      field(:template_version, :integer)
      field(:forked, :boolean, default: false)
      field(:links, {:array, :string}, default: [])
      field(:status, :string)
      field(:open_layer, :integer)
      field(:opened_by, :string)
      field(:opened_at, :utc_datetime_usec)
      field(:completed_at, :utc_datetime_usec)
      field(:note, :string)
      # Its place in the backlog (sunna#103): its batch, its rank (in the
      # backlog, or in its batch), and whether it is open, alone.
      field(:batch, :integer)
      field(:rank, :integer)
      field(:open, :boolean, default: false)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Activity do
    @moduledoc """
    An activity: its layer and place in it, type, assignee, status, and
    `view` as the screens read it (ready, waiting, active, blocked,
    failed, done, skipped), with what it waits on and its pins.
    """
    use Ecto.Schema
    @primary_key false
    schema "sunna_queue_activity" do
      field(:household_id, :binary_id, primary_key: true)
      field(:act_id, :string, primary_key: true)
      field(:task, :integer)
      field(:layer, :integer)
      field(:position, :integer)
      field(:type, :string)
      # Its template's name for it, and the template slot it works on
      # (sunna#90): the name every task made from it shows.
      field(:name, :string)
      field(:slot, :string)
      field(:assignee, :string)
      field(:status, :string)
      field(:view, :string)
      field(:artifact, :string)
      field(:destination, :string)
      field(:action, :string)
      field(:optional, :boolean, default: false)
      field(:throwback, :string)
      field(:imported, :boolean, default: false)
      field(:waits_on, :integer)
      field(:reason, :string)
      field(:pin, :string)
      field(:approved_pin, :string)
      field(:handed_off, :boolean, default: false)
      field(:awaiting_merge, :boolean, default: false)
      field(:result, :string)
      field(:note, :string)
      field(:ready_at, :utc_datetime_usec)
      field(:updated_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule History do
    @moduledoc "One line of a task's history: what happened to which activity, the outcome and pin of a decision, its note, who and when."
    use Ecto.Schema
    @primary_key {:id, :id, autogenerate: true}
    schema "sunna_queue_history" do
      field(:household_id, :binary_id)
      field(:act_id, :string)
      field(:task, :integer)
      field(:what, :string)
      field(:outcome, :string)
      field(:pin, :string)
      field(:note, :string)
      field(:actor_kind, :string)
      field(:actor_id, :string)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Template do
    @moduledoc "A template as data (§7): its title and layers, `%{\"layers\" => [[spec]]}`."
    use Ecto.Schema
    @primary_key false
    schema "sunna_queue_template" do
      field(:household_id, :binary_id, primary_key: true)
      field(:name, :string, primary_key: true)
      field(:title, :string)
      field(:layers, :map)
      # How many times it has been defined (sunna#90).
      field(:version, :integer, default: 0)
      field(:defined_by, :string)
      field(:defined_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Document do
    @moduledoc "A document attached to a task beside its activities' (sunna#91): its citation, its key (the path without its pin) and its role, a slot name or `source`."
    use Ecto.Schema
    @primary_key false
    schema "sunna_queue_document" do
      field(:household_id, :binary_id, primary_key: true)
      field(:task, :integer, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:citation, :string)
      field(:role, :string)
      field(:attached_by, :string)
      field(:attached_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Batch do
    @moduledoc "A numbered batch of the backlog (sunna#103): its name, rank and whether it is open."
    use Ecto.Schema
    @primary_key false
    schema "sunna_queue_batch" do
      field(:household_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:name, :string)
      field(:made_at, :utc_datetime_usec)
      field(:rank, :integer)
      field(:open, :boolean, default: false)
    end

    @type t :: %__MODULE__{}
  end

  defmodule State do
    @moduledoc "The queue's own state: whether the household has cut over (§6.2), and at which commit."
    use Ecto.Schema
    @primary_key false
    schema "sunna_queue_state" do
      field(:household_id, :binary_id, primary_key: true)
      field(:cut_over, :boolean, default: false)
      # The house queue's one switch (sunna#94).
      field(:paused, :boolean, default: false)
      field(:paused_at, :utc_datetime_usec)
      field(:cut_at, :utc_datetime_usec)
      field(:commit, :string)
      field(:note, :string)
    end

    @type t :: %__MODULE__{}
  end
end
