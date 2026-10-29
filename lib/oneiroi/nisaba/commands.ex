defmodule Oneiroi.Nisaba.Commands do
  @moduledoc "The ledger aggregate's commands."

  defmodule SetBudget do
    use Oneiroi.Command, fields: [:id, :purpose, :cap_nanos, :period]
  end

  defmodule RecordModelCall do
    use Oneiroi.Command,
      fields: [
        :id,
        :ref,
        :purpose,
        :model,
        :prompt_tokens,
        :completion_tokens,
        :cost_nanos,
        :estimated
      ]
  end
end
