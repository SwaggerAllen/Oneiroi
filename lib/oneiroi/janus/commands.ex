defmodule Oneiroi.Janus.Commands do
  @moduledoc "The succession's commands (janus#3); `id` is the original resident's id."

  defmodule ProposeSuccession do
    use Oneiroi.Command, decision: true, fields: [:id, :dry_run]
  end

  defmodule OpenSuccession do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule DeclineSuccession do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule WithdrawSuccession do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule StopSuccession do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule RecordFork do
    use Oneiroi.Command, fields: [:id, :episode, :copy_id, :sequence, :commit, :events]
  end

  defmodule FailFork do
    use Oneiroi.Command, fields: [:id, :episode, :reason]
  end

  defmodule SetBackup do
    use Oneiroi.Command, fields: [:id, :url, :token_ciphertext, :visibility, :push]
  end
end
