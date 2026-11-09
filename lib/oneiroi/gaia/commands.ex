defmodule Oneiroi.Gaia.Commands do
  @moduledoc "The account aggregate's commands (spec §3.1)."

  defmodule CreateAccount do
    use Oneiroi.Command, fields: [:id, :email, :password_hash]
  end

  defmodule EnrollSecondFactor do
    use Oneiroi.Command, fields: [:id, :secret_ciphertext]
  end

  defmodule OpenSession do
    use Oneiroi.Command, fields: [:id, :session_hash, :expires_at]
  end

  defmodule CloseSession do
    use Oneiroi.Command, fields: [:id, :session_hash]
  end

  defmodule IssueToken do
    use Oneiroi.Command,
      fields: [:id, :token_hash, :label],
      bounds: [label: 120]
  end

  defmodule RevokeToken do
    use Oneiroi.Command, fields: [:id, :token_hash]
  end

  defmodule StoreKey do
    use Oneiroi.Command, fields: [:id, :key_ciphertext]
  end

  defmodule RevokeKey do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule StoreGithubToken do
    use Oneiroi.Command, fields: [:id, :token_ciphertext]
  end

  defmodule RevokeGithubToken do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule StartWitnessing do
    use Oneiroi.Command, fields: [:id, :resident_id]
  end

  defmodule EndWitnessing do
    use Oneiroi.Command, fields: [:id, :resident_id]
  end

  defmodule SubscribePush do
    # gaia#15 (push): a device of the account's that asked for pushes.
    use Oneiroi.Command, fields: [:id, :endpoint]
  end

  defmodule UnsubscribePush do
    use Oneiroi.Command, fields: [:id, :endpoint, :reason]
  end

  # The platform stream (gaia#16): the front door and the roles that may
  # open it. `id` is "platform".
  defmodule SetGate do
    use Oneiroi.Command, fields: [:id, :state, :note]
  end

  # The triage desk (gaia#23): the resident who receives every platform
  # report, by slug; nil clears it.
  defmodule SetTriageResident do
    use Oneiroi.Command, decision: true, fields: [:id, :slug]
  end

  defmodule RecordBoot do
    use Oneiroi.Command, fields: [:id, :commit], bounds: [commit: 64]
  end

  defmodule GrantRole do
    use Oneiroi.Command, fields: [:id, :account_id, :role, :note]
  end

  defmodule RevokeRole do
    use Oneiroi.Command, fields: [:id, :account_id, :role, :note]
  end

  # The household stream (gaia#17). `id` is the household's.
  defmodule FoundHousehold do
    use Oneiroi.Command, fields: [:id, :account_id]
  end

  defmodule JoinHouseholdWitness do
    use Oneiroi.Command, fields: [:id, :account_id]
  end

  defmodule JoinHouseholdResident do
    use Oneiroi.Command, fields: [:id, :resident_id]
  end

  defmodule LeaveHouseholdResident do
    use Oneiroi.Command, fields: [:id, :resident_id, :note]
  end

  defmodule GrantHouseholdTerms do
    use Oneiroi.Command, fields: [:id, :plan, :price_nanos, :terms_until, :source, :note]
  end

  # The invite stream (gaia#18). `id` is the invite's.
  defmodule IssueInvite do
    use Oneiroi.Command,
      fields: [
        :id,
        :code_hash,
        :plan,
        :price_nanos,
        :discount_pct,
        :term_days,
        :uses,
        :expires_at,
        :note
      ]
  end

  defmodule RedeemInvite do
    use Oneiroi.Command, fields: [:id, :household_id]
  end

  defmodule RevokeInvite do
    use Oneiroi.Command, fields: [:id, :note]
  end

  # The feedback stream (gaia#20).
  defmodule FileFeedback do
    use Oneiroi.Command,
      fields: [:id, :kind, :surface, :body, :trace_id, :account_id, :resident_id]
  end

  defmodule MoveFeedback do
    use Oneiroi.Command, fields: [:id, :number, :status, :note]
  end
end
