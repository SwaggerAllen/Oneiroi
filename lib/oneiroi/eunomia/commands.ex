defmodule Oneiroi.Eunomia.Commands do
  @moduledoc "The regression suite's commands; `id` is the resident's id."

  defmodule WriteTest do
    use Oneiroi.Command, fields: [:id, :prompt, :passes_if, :fails_if]
  end

  defmodule ChangeTest do
    use Oneiroi.Command, fields: [:id, :number, :prompt, :passes_if, :fails_if]
  end

  defmodule StartRun do
    use Oneiroi.Command, fields: [:id, :run_ref, :models, :tests, :behaviours, :commitments]
  end

  defmodule RecordAnswer do
    use Oneiroi.Command,
      fields: [
        :id,
        :run_ref,
        :card_ref,
        :model,
        :test_number,
        :behaviour_number,
        :commitment_number,
        :content,
        :refusal,
        :failure
      ]
  end

  defmodule FinishRun do
    use Oneiroi.Command, fields: [:id, :run_ref]
  end

  defmodule FailRun do
    use Oneiroi.Command, fields: [:id, :run_ref, :reason]
  end

  defmodule GradeAnswer do
    use Oneiroi.Command, fields: [:id, :run_ref, :card_ref, :grade]
  end

  defmodule FavouriteAnswer do
    use Oneiroi.Command, fields: [:id, :run_ref, :card_ref]
  end
end
