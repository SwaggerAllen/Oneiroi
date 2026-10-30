defmodule Oneiroi.Ethos.Commands do
  @moduledoc "The character aggregate's commands (spec §6.17)."

  defmodule PlantSeed do
    use Oneiroi.Command, fields: [:id, :number, :text]
  end

  defmodule WiltSeed do
    use Oneiroi.Command, fields: [:id, :number]
  end

  defmodule GraduateSeed do
    # `required` is how many distinct days of citations a seed needs
    # before it may become a habit, read from the setting at the command
    # edge so the aggregate stays pure.
    use Oneiroi.Command, decision: true, fields: [:id, :number, :to_kind, :to_id, :required]
  end

  # A citation may carry its movement (P34 under P38): what the cited
  # moment changed, as `stance`, `intention` and `resume`, string-keyed.
  defmodule CiteSeed do
    use Oneiroi.Command, fields: [:id, :number, :target_kind, :target_id, :movement]
  end

  defmodule DefineHabit do
    use Oneiroi.Command, fields: [:id, :number, :name, :trigger, :stance, :seed_number]
  end

  defmodule ChangeHabit do
    use Oneiroi.Command, fields: [:id, :number, :name, :trigger, :stance]
  end

  defmodule AffirmHabit do
    use Oneiroi.Command, decision: true, fields: [:id, :number]
  end

  defmodule CiteHabit do
    use Oneiroi.Command, fields: [:id, :number, :target_kind, :target_id, :movement]
  end

  defmodule CiteSoulLine do
    use Oneiroi.Command, fields: [:id, :number, :target_kind, :target_id, :movement]
  end

  # Commitments (spec §3.1, P19): a promise to a person, the self that
  # keeps its word; numbered by the resident aggregate like the rest.
  defmodule MakeCommitment do
    use Oneiroi.Command, fields: [:id, :number, :to, :text]
  end

  defmodule KeepCommitment do
    use Oneiroi.Command, decision: true, fields: [:id, :number]
  end

  defmodule ReleaseCommitment do
    use Oneiroi.Command, decision: true, fields: [:id, :number]
  end

  defmodule TakeBaseline do
    # `interval_days` travels on the command so the freshness rule is pure.
    use Oneiroi.Command, fields: [:id, :habits, :spread, :breadth, :interval_days]
  end
end
