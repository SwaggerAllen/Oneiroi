defmodule Oneiroi.Glitnir.Commands do
  @moduledoc "The governance aggregate's commands; `id` is the resident's id."

  defmodule FileReport do
    use Oneiroi.Command, fields: [:id, :text]
  end

  defmodule RecordStep do
    use Oneiroi.Command, decision: true, fields: [:id, :number]
  end

  defmodule ResolveReport do
    use Oneiroi.Command, decision: true, fields: [:id, :number, :outcome, :witness_account_id]
  end
end
