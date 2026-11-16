defmodule Oneiroi.Nisaba.Billing.Stripe do
  @moduledoc """
  Stripe behind the billing port (nisaba#23): a Checkout Session in
  subscription mode for one resident, its price given inline ($20 a month
  by `NISABA_PLAN_PRICE_CENTS`), the resident and the account in its
  metadata and its subscription's, so every webhook names whom it is
  about; and a Customer Portal session for the card and cancelling.
  Form-encoded, as Stripe's API takes it, under the secret key.
  """
  @behaviour Oneiroi.Nisaba.Billing

  alias Oneiroi.Config
  alias Oneiroi.Nisaba.Billing
  alias Oneiroi.Nisaba.Error

  @impl true
  def checkout(p) do
    form =
      [
        {"mode", "subscription"},
        {"success_url", p.success_url},
        {"cancel_url", p.cancel_url},
        {"client_reference_id", p.resident_id},
        {"line_items[0][quantity]", "1"},
        {"line_items[0][price_data][currency]", "usd"},
        {"line_items[0][price_data][unit_amount]", Integer.to_string(p.cents)},
        {"line_items[0][price_data][recurring][interval]", "month"},
        {"line_items[0][price_data][product_data][name]", "Keeping #{p.name}"},
        {"metadata[resident_id]", p.resident_id},
        {"metadata[account_id]", p.account_id},
        {"subscription_data[metadata][resident_id]", p.resident_id},
        {"subscription_data[metadata][account_id]", p.account_id}
      ] ++ who(p)

    post("/checkout/sessions", form)
  end

  @impl true
  def portal(customer, return_url),
    do: post("/billing_portal/sessions", [{"customer", customer}, {"return_url", return_url}])

  defp who(%{customer: c}) when is_binary(c), do: [{"customer", c}]
  defp who(%{email: e}) when is_binary(e), do: [{"customer_email", e}]
  defp who(_p), do: []

  defp post(path, form) do
    case Billing.unwrap(Config.fetch!(:nisaba, :stripe_secret_key)) do
      nil -> {:error, Error.new(:nisaba_billing_off, :nisaba_stripe_no_key)}
      key -> request(path, form, key)
    end
  end

  defp request(path, form, key) do
    # A payment provider, not a model provider: the billing port's two
    # calls (nisaba#23), registered in Nisaba's externals with its fake.
    # oneiroi:allow model_port
    case Req.post(Config.fetch!(:nisaba, :stripe_url) <> path,
           form: form,
           auth: {:bearer, key},
           retry: false,
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"url" => url}}} when is_binary(url) ->
        {:ok, url}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         Error.new(:nisaba_billing_failed, :nisaba_stripe_refused,
           reason: {:status, status, get_in(body, ["error", "message"])}
         )}

      {:error, exception} ->
        {:error, Error.caught(:nisaba_billing_failed, :nisaba_stripe_transport, exception)}
    end
  end
end
