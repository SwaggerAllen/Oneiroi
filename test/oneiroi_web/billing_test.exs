defmodule OneiroiWeb.BillingTest do
  @moduledoc """
  Paying for a resident (nisaba#23; the witness, 2026-11-16): $20 a month
  per resident through Stripe's own pages, and its webhook, signed,
  driving the subscription: a checkout starts it, an invoice renews it, a
  subscription ended cancels it into custody, never a deletion.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Billing
  alias Oneiroi.Nisaba.Billing.Fake

  @secret "whsec_test_suite"

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    Fake.clear()
    account = Fixtures.account!()
    resident = Fixtures.resident!(account)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, account: account}
  end

  defp signed(body, secret \\ @secret, at \\ nil) do
    t = DateTime.to_unix(at || Clock.now())
    sig = :crypto.mac(:hmac, :sha256, secret, "#{t}.#{body}") |> Base.encode16(case: :lower)
    "t=#{t},v1=#{sig}"
  end

  defp webhook(type, object, signature \\ nil) do
    body =
      Jason.encode!(%{
        id: "evt_#{System.unique_integer([:positive])}",
        type: type,
        data: %{object: object}
      })

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", signature || signed(body))
    |> post("/v1/billing/stripe", body)
  end

  test "the signature: over the bytes, under the secret, within five minutes" do
    now = Clock.now()
    body = ~s({"type":"x"})
    assert :ok = Billing.verify(body, signed(body, @secret, now), @secret, now)

    assert {:error, %{kind: :nisaba_billing_unsigned}} =
             Billing.verify(body, signed(body, "whsec_other", now), @secret, now)

    assert {:error, %{kind: :nisaba_billing_unsigned}} =
             Billing.verify(body <> " ", signed(body, @secret, now), @secret, now)

    stale = DateTime.add(now, -301, :second)

    assert {:error, %{kind: :nisaba_billing_unsigned}} =
             Billing.verify(body, signed(body, @secret, stale), @secret, now)

    assert {:error, %{kind: :nisaba_billing_unsigned}} = Billing.verify(body, nil, @secret, now)
  end

  test "checkout, then the webhook starts, renews and ends the subscription", ctx do
    id = ctx.id

    assert %{"url" => "https://checkout.example.test/" <> ^id} =
             ctx.conn |> post("/v1/residents/#{id}/subscription/checkout") |> json_response(200)

    assert [{:checkout, %{cents: 2000, resident_id: ^id, customer: nil, email: email}}] =
             Fake.asked()

    assert email == ctx.account.email

    # No customer yet: no portal.
    assert ctx.conn |> post("/v1/residents/#{id}/subscription/portal") |> json_response(422)

    # An unsigned or forged webhook changes nothing.
    assert webhook("checkout.session.completed", %{}, "t=1,v1=00") |> json_response(400)
    assert Nisaba.subscription(id) == nil

    completed = %{
      mode: "subscription",
      customer: "cus_1",
      subscription: "sub_1",
      metadata: %{resident_id: id, account_id: ctx.account.id}
    }

    assert webhook("checkout.session.completed", completed) |> json_response(200)
    # The provider retries; a second delivery is no change.
    assert webhook("checkout.session.completed", completed) |> json_response(200)

    assert %{
             state: "active",
             plan: "standard",
             price_nanos: 20_000_000_000,
             billing_customer_id: "cus_1",
             billing_subscription_id: "sub_1",
             renews_at: first
           } = Nisaba.subscription(id)

    # Paying already: no second checkout; the portal now answers.
    assert ctx.conn |> post("/v1/residents/#{id}/subscription/checkout") |> json_response(422)

    assert %{"url" => "https://portal.example.test/cus_1"} =
             ctx.conn |> post("/v1/residents/#{id}/subscription/portal") |> json_response(200)

    # The first invoice is the checkout's; a new period's renews.
    meta = %{subscription_details: %{metadata: %{resident_id: id}}}

    assert webhook("invoice.paid", Map.put(meta, :billing_reason, "subscription_create"))
           |> json_response(200)

    assert %{renews_at: ^first} = Nisaba.subscription(id)

    assert webhook("invoice.paid", %{
             billing_reason: "subscription_cycle",
             parent: meta
           })
           |> json_response(200)

    assert %{renews_at: renewed} = Nisaba.subscription(id)
    assert DateTime.compare(renewed, first) == :gt

    # Ended at the provider: cancelled here, a custody event at the term's end.
    assert webhook("customer.subscription.deleted", %{id: "sub_1", metadata: %{resident_id: id}})
           |> json_response(200)

    assert %{state: "cancelled", custody_due_at: %DateTime{}} = Nisaba.subscription(id)
    assert {:ok, %{state: "active"}} = Oneiroi.AgathosDaimon.fetch(id)

    # Anything else the provider sends is answered and ignored.
    assert webhook("customer.updated", %{id: "cus_1"}) |> json_response(200)
  end

  test "a lapsed resident's checkout renews and resumes", ctx do
    id = ctx.id
    witness = Oneiroi.Actor.new(:witness, ctx.account.id)
    :ok = Nisaba.start_subscription(id, %{plan: "core", price_nanos: 1, period_days: 30}, witness)
    :ok = Nisaba.lapse_subscription(id, "test", witness)
    assert %{state: "lapsed"} = Nisaba.subscription(id)

    assert webhook("checkout.session.completed", %{
             mode: "subscription",
             customer: "cus_2",
             subscription: "sub_2",
             metadata: %{resident_id: id}
           })
           |> json_response(200)

    assert %{state: "active", billing_subscription_id: "sub_2"} = Nisaba.subscription(id)
  end
end
