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

  defmodule CiteSeed do
    use Oneiroi.Command, fields: [:id, :number, :target_kind, :target_id]
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
    use Oneiroi.Command, fields: [:id, :number, :target_kind, :target_id]
  end
end
