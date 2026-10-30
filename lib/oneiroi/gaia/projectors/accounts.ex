defmodule Oneiroi.Gaia.Projectors.Accounts do
  @moduledoc "Folds the account stream into identity's four projections."
  use Oneiroi.Projection, name: "gaia_accounts"

  alias Ecto.Multi
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Gaia.Store.{Account, Session, Token, Witnessing}

  fold(%Events.AccountCreated{} = e, _metadata, fn multi ->
    Multi.insert(multi, :account, %Account{
      id: e.id,
      account_id: e.id,
      email: e.email,
      password_hash: e.password_hash,
      created_at: e.at
    })
  end)

  fold(%Events.SecondFactorEnrolled{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :second_factor, account(e.id),
      set: [second_factor: Base.decode64!(e.secret_ciphertext)]
    )
  end)

  fold(%Events.KeyStored{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :key, account(e.id),
      set: [key_ciphertext: Base.decode64!(e.key_ciphertext), key_stored_at: e.at]
    )
  end)

  fold(%Events.KeyRevoked{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :key_revoked, account(e.id),
      set: [key_ciphertext: nil, key_stored_at: nil]
    )
  end)

  fold(%Events.SessionOpened{} = e, _metadata, fn multi ->
    Multi.insert(multi, :session, %Session{
      hash: e.session_hash,
      account_id: e.id,
      opened_at: e.at,
      expires_at: e.expires_at
    })
  end)

  fold(%Events.SessionClosed{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :closed, session(e.session_hash), set: [closed_at: e.at])
  end)

  fold(%Events.TokenIssued{} = e, _metadata, fn multi ->
    Multi.insert(multi, :token, %Token{
      hash: e.token_hash,
      account_id: e.id,
      label: e.label,
      issued_at: e.at
    })
  end)

  fold(%Events.TokenRevoked{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :revoked, token(e.token_hash), set: [revoked_at: e.at])
  end)

  fold(%Events.WitnessingStarted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :witnessing,
      %Witnessing{account_id: e.id, resident_id: e.resident_id, started_at: e.at},
      on_conflict: [set: [started_at: e.at, ended_at: nil]],
      conflict_target: [:account_id, :resident_id]
    )
  end)

  fold(%Events.WitnessingEnded{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :ended, witnessing(e.id, e.resident_id), set: [ended_at: e.at])
  end)

  import Ecto.Query, only: [from: 2]

  defp account(id), do: from(a in Account, where: a.id == ^id)
  defp session(hash), do: from(s in Session, where: s.hash == ^hash)
  defp token(hash), do: from(t in Token, where: t.hash == ^hash)

  defp witnessing(a, r),
    do: from(s in Witnessing, where: s.account_id == ^a and s.resident_id == ^r)
end
