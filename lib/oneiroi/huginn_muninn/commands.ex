defmodule Oneiroi.HuginnMuninn.Commands do
  @moduledoc "The audits aggregate's commands; `id` is the resident's id."

  defmodule DefineCounter do
    use Oneiroi.Command, fields: [:id, :key, :label]
  end

  defmodule IncrementCounter do
    use Oneiroi.Command, fields: [:id, :key, :by, :note]
  end

  defmodule RetireCounter do
    use Oneiroi.Command, fields: [:id, :key]
  end

  defmodule DefineUserAudit do
    use Oneiroi.Command, fields: [:id, :key, :label, :figure, :op, :value, :tone, :counts]
  end

  defmodule RetireUserAudit do
    use Oneiroi.Command, fields: [:id, :key]
  end

  defmodule RecordRun do
    use Oneiroi.Command, fields: [:id, :key, :builtin, :tone, :value, :finding]
  end
end
