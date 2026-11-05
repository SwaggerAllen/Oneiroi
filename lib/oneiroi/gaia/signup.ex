defmodule Oneiroi.Gaia.Signup do
  @moduledoc """
  Sign-up behind the front door (gaia#19). The gate decides:

  - `closed`: nobody signs up (`gaia_door_closed`).
  - `invite`: a code is required, checked before anything is created, and
    redeemed onto the new account's household once it is founded.
  - `open`: anyone; a code, if given, is redeemed the same way.

  The account is created by the platform, since no principal exists yet;
  its household is founded in the same dispatch (the household handler,
  gaia#17), so the code's terms land on it at once. The password arrives
  wrapped (`Oneiroi.Config.Secret`) and is unwrapped only where it is
  hashed. No email verification yet: under `invite` the code is the
  proof a trusted hand let this person in; verification comes before the
  gate opens (the witness's call, 2026-11-05).

  A code spent between its check and its redemption by someone else
  leaves the account created without terms; the refusal says so, and
  the person can log in and redeem another.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Config.Secret
  alias Oneiroi.Gaia.Accounts
  alias Oneiroi.Gaia.Door
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Households
  alias Oneiroi.Gaia.Invites

  @min_password 10

  @doc "Signs up under the gate: `{:ok, account_id}` or the refusal naming why."
  def sign_up(email, %Secret{} = password, code) do
    code = blank_to_nil(code)

    with :ok <- door(Door.gate().state, code),
         :ok <- credentials(email, password),
         # The code before the email: behind an invite door, someone
         # without a code learns nothing about which emails hold accounts.
         :ok <- valid_code(code),
         :ok <- unused(email),
         {:ok, id} <- Accounts.create(email, Secret.unwrap(password), Actor.platform()),
         :ok <- redeem(code, id) do
      {:ok, id}
    end
  end

  defp door("closed", _code),
    do: {:error, Error.new(:gaia_door_closed, :gaia_signup_door_closed)}

  defp door("invite", nil),
    do: {:error, Error.new(:gaia_invite_required, :gaia_signup_invite_required)}

  defp door(_open_or_invite, _code), do: :ok

  defp credentials(email, password) do
    cond do
      not (is_binary(email) and String.match?(String.trim(email), ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)) ->
        {:error, Error.new(:gaia_signup_invalid, :gaia_signup_email_invalid)}

      not (is_binary(Secret.unwrap(password)) and
               String.length(Secret.unwrap(password)) >= @min_password) ->
        {:error,
         Error.new(:gaia_signup_invalid, :gaia_signup_password_short, at_least: @min_password)}

      true ->
        :ok
    end
  end

  defp unused(email) do
    if Accounts.id_for(String.trim(email)),
      do: {:error, Error.new(:gaia_email_taken, :gaia_signup_email_taken)},
      else: :ok
  end

  defp valid_code(nil), do: :ok

  defp valid_code(code) do
    with {:ok, _sku} <- Invites.check(code), do: :ok
  end

  defp redeem(nil, _id), do: :ok

  defp redeem(code, id) do
    case Invites.redeem(code, Households.household_id(id), Actor.new(:witness, id)) do
      {:ok, _sku} -> :ok
      {:error, e} -> {:error, %{e | details: Keyword.put(e.details, :account_created, id)}}
    end
  end

  defp blank_to_nil(code) when is_binary(code),
    do: if(String.trim(code) == "", do: nil, else: code)

  defp blank_to_nil(_code), do: nil
end
