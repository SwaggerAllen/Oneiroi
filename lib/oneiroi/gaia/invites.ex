defmodule Oneiroi.Gaia.Invites do
  @moduledoc """
  Invite codes (gaia#18): issued by a super admin as a SKU, redeemed onto
  a household as its terms, revoked with a note.

  A code is twelve characters from an alphabet without the ones people
  misread (`0 O 1 I L`), shown as three groups of four, and shown once,
  at issue: the log and the tables hold only its SHA-256, over the code
  with case, spaces and dashes taken out, so a typed code matches however
  it was typed.

  A redemption grants the household the SKU's terms: its plan, its list
  price less the discount, running `term_days` from the redemption, the
  invite named as the source. Nothing is charged; the price is what the
  terms say, the day billing reads them.

  The SKU defaults are the list price ($20 a month, the witness's word,
  2026-11-05) at a full discount, ninety days, one use and no expiry:
  the alpha's free code, set in one place.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Door
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Households
  alias Oneiroi.Gaia.InviteRouter
  alias Oneiroi.Gaia.Store
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @alphabet ~c"23456789ABCDEFGHJKMNPQRSTUVWXYZ"
  @day 86_400

  @doc "The SKU a code is issued with when the operator names nothing else."
  def defaults,
    do: %{
      plan: "monthly",
      price_nanos: 20_000_000_000,
      discount_pct: 100,
      term_days: 90,
      uses: 1,
      expires_at: nil
    }

  @doc "Issues a code; a super admin's alone, with a note. Answers the code, the only time it is shown."
  def issue(sku, note, %Actor{} = actor) do
    with :ok <- operator(actor) do
      sku = Map.merge(defaults(), sku)
      id = Ecto.UUID.generate()
      code = code()

      command = %Commands.IssueInvite{
        actor: actor,
        at: Clock.now(),
        id: id,
        code_hash: hash(code),
        plan: sku.plan,
        price_nanos: sku.price_nanos,
        discount_pct: sku.discount_pct,
        term_days: sku.term_days,
        uses: sku.uses,
        expires_at: sku.expires_at,
        note: note
      }

      with :ok <- dispatch(command), do: {:ok, %{id: id, code: code}}
    end
  end

  @doc "Revokes a code; a super admin's alone, with a note."
  def revoke(id, note, %Actor{} = actor) do
    with :ok <- operator(actor),
         do: dispatch(%Commands.RevokeInvite{actor: actor, at: Clock.now(), id: id, note: note})
  end

  @doc """
  What a code would grant, or why it would not, without spending it: the
  sign-up form's check. `{:ok, sku}`, or an error naming unknown,
  revoked, expired or spent.
  """
  def check(code) do
    case find(code) do
      nil -> {:error, Error.new(:gaia_invite_unknown, :gaia_invite_check_unknown)}
      row -> standing(row)
    end
  end

  defp standing(row) do
    cond do
      row.revoked_at ->
        {:error, Error.new(:gaia_invite_revoked, :gaia_invite_check_revoked)}

      row.expires_at && DateTime.compare(Clock.now(), row.expires_at) != :lt ->
        {:error, Error.new(:gaia_invite_expired, :gaia_invite_check_expired)}

      row.redeemed >= row.uses ->
        {:error, Error.new(:gaia_invite_spent, :gaia_invite_check_spent)}

      true ->
        {:ok, sku(row)}
    end
  end

  @doc """
  Redeems a code onto the household: the invite records the use, then the
  platform grants the household the code's terms.
  """
  def redeem(code, household_id, %Actor{} = actor) do
    with %Store.Invite{} = row <- find(code) || unknown(),
         :ok <-
           dispatch(%Commands.RedeemInvite{
             actor: actor,
             at: Clock.now(),
             id: row.id,
             household_id: household_id
           }),
         :ok <-
           Households.grant_terms(
             household_id,
             terms(row),
             "an invite redeemed: #{row.note}",
             Actor.platform()
           ) do
      {:ok, sku(row)}
    end
  end

  @doc "Every code issued, newest first, with its standing; never the code."
  def list do
    Scope.platform(fn -> Repo.all(from(i in Store.Invite, order_by: [desc: i.issued_at])) end)
    |> Enum.map(fn row ->
      Map.merge(sku(row), %{
        id: row.id,
        redeemed: row.redeemed,
        note: row.note,
        issued_at: row.issued_at,
        revoked_at: row.revoked_at,
        revoke_note: row.revoke_note
      })
    end)
  end

  defp terms(row) do
    %{
      plan: row.plan,
      price_nanos: price(row),
      until: DateTime.add(Clock.now(), row.term_days * @day, :second),
      source: "invite:#{row.id}"
    }
  end

  defp sku(row),
    do: %{
      plan: row.plan,
      list_price_nanos: row.price_nanos,
      discount_pct: row.discount_pct,
      price_nanos: price(row),
      term_days: row.term_days,
      uses: row.uses,
      expires_at: row.expires_at
    }

  defp price(row), do: div(row.price_nanos * (100 - row.discount_pct), 100)

  defp find(code) when is_binary(code) do
    digest = hash(code)
    Scope.platform(fn -> Repo.one(from(i in Store.Invite, where: i.code_hash == ^digest)) end)
  end

  defp find(_code), do: nil

  defp unknown, do: {:error, Error.new(:gaia_invite_unknown, :gaia_invite_redeem_unknown)}

  @doc false
  def hash(code) do
    normal = code |> String.upcase() |> String.replace(~r/[\s-]/, "")
    :crypto.hash(:sha256, normal) |> Base.encode16(case: :lower)
  end

  defp code do
    n = length(@alphabet)

    for(<<byte <- :crypto.strong_rand_bytes(12)>>, do: Enum.at(@alphabet, rem(byte, n)))
    |> to_string()
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join("-", &Enum.join/1)
  end

  defp operator(%Actor{kind: :witness, id: id}) do
    if Door.operator?(id),
      do: :ok,
      else: {:error, Error.new(:gaia_not_an_operator, :gaia_invite_not_operator)}
  end

  defp operator(%Actor{}),
    do: {:error, Error.new(:gaia_not_an_operator, :gaia_invite_not_a_witness)}

  defp dispatch(command) do
    case InviteRouter.dispatch(command) do
      {:ok, _events} ->
        :ok

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:gaia_dispatch_failed, :gaia_invite_dispatch_failed, reason)}
    end
  end
end
