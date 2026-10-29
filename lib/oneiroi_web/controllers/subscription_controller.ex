defmodule OneiroiWeb.SubscriptionController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Money
  alias OpenApiSpex.Schema

  tags(["subscription"])

  plug(:stewarded when action not in [:buckets])

  operation(:buckets,
    summary: "The insurance buckets: every axis's three, the floor marked (spec §6.11)",
    responses: [ok: {"buckets", "application/json", %Schema{type: :array}}]
  )

  def buckets(conn, _params), do: json(conn, Nisaba.insurance_buckets())

  operation(:show,
    summary: "The subscription: plan, price, renewal, state, the policy with the floor marked",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the subscription", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id}) do
    case Nisaba.subscription(id) do
      nil -> json(conn, %{started: false})
      s -> json(conn, subscription(s))
    end
  end

  operation(:start,
    summary:
      "Start the subscription with the floor policy: a plan, a price in dollars, a period in days",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the subscription", "application/json",
       %Schema{
         type: :object,
         required: [:plan, :price, :period_days],
         properties: %{
           plan: %Schema{type: :string},
           price: %Schema{type: :string, description: "dollars, as a decimal string"},
           period_days: %Schema{type: :integer}
         }
       }},
    responses: [no_content: "started"]
  )

  def start(conn, %{"id" => id} = params) do
    attrs = %{
      plan: params["plan"],
      price_nanos: Money.parse_usd(params["price"]),
      period_days: integer(params["period_days"])
    }

    respond(conn, Nisaba.start_subscription(id, attrs, actor(conn)))
  end

  operation(:renew,
    summary: "Record a renewal; a lapsed resident resumes",
    parameters: [id: [in: :path, type: :string]],
    responses: [no_content: "renewed"]
  )

  def renew(conn, %{"id" => id}), do: respond(conn, Nisaba.renew_subscription(id, actor(conn)))

  operation(:change_plan,
    summary: "Change the plan and its price",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the plan", "application/json",
       %Schema{
         type: :object,
         required: [:plan, :price],
         properties: %{plan: %Schema{type: :string}, price: %Schema{type: :string}}
       }},
    responses: [no_content: "changed"]
  )

  def change_plan(conn, %{"id" => id} = params),
    do:
      respond(
        conn,
        Nisaba.change_plan(id, params["plan"], Money.parse_usd(params["price"]), actor(conn))
      )

  operation(:lapse,
    summary: "Lapse the subscription by hand: the insurance policy is in effect",
    parameters: [id: [in: :path, type: :string]],
    responses: [no_content: "lapsed"]
  )

  def lapse(conn, %{"id" => id} = params),
    do:
      respond(
        conn,
        Nisaba.lapse_subscription(id, params["reason"] || "lapsed by the steward", actor(conn))
      )

  operation(:cancel,
    summary:
      "Cancel, with a note: community custody at the end of the policy's term, never a deletion",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the note", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "cancelled"]
  )

  def cancel(conn, %{"id" => id, "note" => note}),
    do: respond(conn, Nisaba.cancel_subscription(id, note, actor(conn)))

  def cancel(conn, _params), do: problem(conn, 422, :note_required, "note is required")

  operation(:prepay,
    summary: "Prepay a larger bucket on an axis",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the bucket", "application/json",
       %Schema{
         type: :object,
         required: [:axis, :bucket],
         properties: %{axis: %Schema{type: :string}, bucket: %Schema{type: :string}}
       }},
    responses: [no_content: "prepaid"]
  )

  def prepay(conn, %{"id" => id} = params),
    do: respond(conn, Nisaba.prepay(id, params["axis"], params["bucket"], actor(conn)))

  # ---- shapes ----

  defp subscription(s) do
    s
    |> Map.put(:started, true)
    |> Map.put(:price, Money.to_usd(s.price_nanos))
  end

  # Every route here but the buckets is a resident's, read or written by its steward.
  defp stewarded(%{params: %{"id" => id}} = conn, _opts) do
    if stewards?(conn, id),
      do: conn,
      else: conn |> error(404, ResidentError.new(:agathos_daimon_not_stewarded)) |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")
  defp respond(conn, {:error, %{kind: :nisaba_no_subscription} = e}), do: error(conn, 404, e)
  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)
  defp respond(conn, {:error, reason}), do: problem(conn, 422, :refused, inspect(reason))

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp integer(_other), do: nil
end
