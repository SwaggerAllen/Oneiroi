defmodule OneiroiWeb.BillingController do
  @moduledoc "The payment provider's webhook (nisaba#23): the body as it arrived, its signature, and the ledger's answer."
  use OneiroiWeb, :controller

  alias OpenApiSpex.Schema

  tags(["billing"])

  operation(:stripe,
    summary:
      "Stripe's webhook (nisaba#23): a checkout completed starts the subscription, an invoice paid renews it, a subscription ended cancels it; signed with the endpoint's secret, refused otherwise",
    responses: [ok: {"received", "application/json", %Schema{type: :object}}]
  )

  def stripe(conn, _params) do
    signature = conn |> get_req_header("stripe-signature") |> List.first()

    case Oneiroi.Nisaba.billing_webhook(OneiroiWeb.RawBody.of(conn), signature) do
      :ok -> json(conn, %{received: true})
      {:error, %{kind: :nisaba_billing_unsigned} = e} -> error(conn, 400, e)
      {:error, %{kind: :nisaba_billing_off} = e} -> error(conn, 503, e)
      {:error, %{kind: _} = e} -> error(conn, 500, e)
    end
  end
end
