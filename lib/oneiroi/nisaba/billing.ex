defmodule Oneiroi.Nisaba.Billing do
  @moduledoc """
  Paying for a resident (nisaba#23, spec F53; the witness, 2026-11-16:
  $20 a month per resident, Stripe-hosted). The port is two calls, a
  checkout page and the provider's own page for the card and the
  cancellation; the rest is the provider's webhook, verified here and
  turned into the subscription's own commands:

  - a checkout completed starts the subscription (or renews a lapsed
    one) and links the provider's ids to it;
  - an invoice paid for a new period renews it;
  - a subscription ended at the provider cancels it here: a custody
    event at the end of the policy's term, never a deletion (nisaba#18).

  A payment that fails is not an event here: no renewal arrives, and the
  nightly pass lapses the subscription once its grace has run (nisaba#17).
  Card numbers and addresses never reach the platform; the provider's
  customer and subscription ids are all it keeps.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.Nisaba.Error
  alias Oneiroi.Nisaba.Subscriptions

  @callback checkout(params :: map()) :: {:ok, String.t()} | {:error, term()}
  @callback portal(customer :: String.t(), return_url :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @actor Actor.new(:job, "nisaba_billing")
  @plan "standard"
  @period_days 30
  # A signed webhook older than this is refused, the provider's own advice.
  @tolerance 300

  @doc "The provider's checkout page for this resident's subscription: its URL."
  def checkout(resident_id, resident_name, %{account_id: account_id, email: email}, return_url) do
    cents = Config.fetch!(:nisaba, :plan_price_cents)

    params = %{
      resident_id: resident_id,
      account_id: account_id,
      name: resident_name,
      email: email,
      customer: customer_of(resident_id),
      cents: cents,
      success_url: return_url,
      cancel_url: return_url
    }

    case Subscriptions.subscription(resident_id) do
      %{state: "active", billing_subscription_id: s} when is_binary(s) ->
        {:error, Error.new(:nisaba_billing_failed, :nisaba_checkout_already_paying)}

      %{state: "cancelled"} ->
        {:error, Error.new(:nisaba_cancelled, :nisaba_checkout_cancelled)}

      _other ->
        client().checkout(params)
    end
  end

  @doc "The provider's own page for the card, the invoices and cancelling: its URL."
  def portal(resident_id, return_url) do
    case customer_of(resident_id) do
      nil -> {:error, Error.new(:nisaba_no_subscription, :nisaba_portal_no_customer)}
      customer -> client().portal(customer, return_url)
    end
  end

  @doc "A webhook, verified against its signature, then acted on; anything unasked for is answered and ignored."
  def webhook(raw, signature) when is_binary(raw) do
    with {:ok, secret} <- webhook_secret(),
         :ok <- verify(raw, signature, secret, Clock.now()),
         {:ok, event} <- Jason.decode(raw) do
      handle(event["type"], get_in(event, ["data", "object"]) || %{})
    else
      {:error, %Jason.DecodeError{}} ->
        {:error, Error.new(:nisaba_billing_unsigned, :nisaba_webhook_unparsed)}

      other ->
        other
    end
  end

  @doc """
  The provider's signature scheme: `t=<unix>,v1=<hex>` over
  `"<t>.<body>"`, HMAC-SHA256 under the endpoint's secret, any `v1`
  matching, the timestamp within five minutes of now.
  """
  def verify(raw, header, secret, %DateTime{} = now) when is_binary(header) do
    parts = header |> String.split(",") |> Enum.map(&String.split(&1, "=", parts: 2))
    stamp = Enum.find_value(parts, fn [k, v] -> if k == "t", do: v end)
    sigs = for [k, v] <- parts, k == "v1", do: v

    with {t, ""} <- Integer.parse(stamp || ""),
         true <- abs(DateTime.to_unix(now) - t) <= @tolerance,
         expected =
           :crypto.mac(:hmac, :sha256, secret, "#{t}.#{raw}") |> Base.encode16(case: :lower),
         true <- Enum.any?(sigs, &same?(&1, expected)) do
      :ok
    else
      _bad -> {:error, Error.new(:nisaba_billing_unsigned, :nisaba_webhook_signature)}
    end
  end

  def verify(_raw, _header, _secret, _now),
    do: {:error, Error.new(:nisaba_billing_unsigned, :nisaba_webhook_unsigned)}

  # Constant-time, as a signature check must be.
  defp same?(a, b) when byte_size(a) == byte_size(b), do: :crypto.hash_equals(a, b)
  defp same?(_a, _b), do: false

  # ---- the provider's events ----

  defp handle("checkout.session.completed", %{"mode" => "subscription"} = o) do
    with resident when is_binary(resident) <- get_in(o, ["metadata", "resident_id"]),
         :ok <- begin(resident),
         do: Subscriptions.link_billing(resident, o["customer"], o["subscription"], @actor),
         else: (nil -> :ok)
  end

  defp handle("invoice.paid", %{"billing_reason" => "subscription_cycle"} = o) do
    case invoice_resident(o) do
      nil -> :ok
      resident -> Subscriptions.renew(resident, @actor)
    end
  end

  defp handle("customer.subscription.deleted", o) do
    with resident when is_binary(resident) <- get_in(o, ["metadata", "resident_id"]),
         %{state: state} when state != "cancelled" <- Subscriptions.subscription(resident) do
      Subscriptions.cancel(resident, "the subscription was ended at the payment provider", @actor)
    else
      _nothing_to_end -> :ok
    end
  end

  defp handle(_type, _object), do: :ok

  defp begin(resident) do
    cents = Config.fetch!(:nisaba, :plan_price_cents)

    case Subscriptions.subscription(resident) do
      nil ->
        Subscriptions.start(
          resident,
          %{plan: @plan, price_nanos: cents * 10_000_000, period_days: @period_days},
          @actor
        )

      %{state: "lapsed"} ->
        Subscriptions.renew(resident, @actor)

      _active_or_ended ->
        :ok
    end
  end

  # The invoice names its subscription's metadata in one of two places,
  # by the API version the endpoint was made under.
  defp invoice_resident(o) do
    get_in(o, ["parent", "subscription_details", "metadata", "resident_id"]) ||
      get_in(o, ["subscription_details", "metadata", "resident_id"])
  end

  defp customer_of(resident_id) do
    case Subscriptions.subscription(resident_id) do
      %{billing_customer_id: c} when is_binary(c) -> c
      _none -> nil
    end
  end

  defp webhook_secret do
    case unwrap(Config.fetch!(:nisaba, :stripe_webhook_secret)) do
      nil -> {:error, Error.new(:nisaba_billing_off, :nisaba_webhook_no_secret)}
      secret -> {:ok, secret}
    end
  end

  @doc false
  def unwrap(nil), do: nil

  def unwrap(secret) do
    case Secret.unwrap(secret) do
      value when is_binary(value) and value != "" -> value
      _empty -> nil
    end
  end

  defp client, do: Config.fetch!(:nisaba, :billing_client)
end
