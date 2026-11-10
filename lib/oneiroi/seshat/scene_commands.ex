defmodule Oneiroi.Seshat.SceneCommands do
  @moduledoc "The scenes aggregate's commands (seshat#52); `id` is the resident's id, `today` her local day at the command's instant."

  defmodule WriteScene do
    use Oneiroi.Command,
      fields: [
        :id,
        :day,
        :title,
        :from_turn,
        :to_turn,
        :from_time,
        :to_time,
        :summary,
        :mood,
        :rounds_ran_out,
        :register,
        :today
      ]
  end

  # `changes`: field name (text) to new value, facts and mood only.
  defmodule CorrectScene do
    use Oneiroi.Command, decision: true, fields: [:id, :day, :number, :changes, :today]
  end

  defmodule CorrectSceneSummary do
    use Oneiroi.Command,
      decision: true,
      fields: [:id, :day, :corrects, :from_turn, :to_turn, :summary]
  end

  defmodule CloseScenes do
    use Oneiroi.Command, fields: [:id, :day]
  end
end
