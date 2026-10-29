defmodule OneiroiWeb.LedgerController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Money
  alias Oneiroi.Nisaba.Period
  alias OpenApiSpex.Schema

  tags(["ledger"])

  operation(:show,
    summary:
      "The resident's ledger: key status, budget lines with this period's spend, and spend by purpose, model and actor since the start of the month",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the ledger", "application/json", %Schema{type: :object}}]
  )

  def show(%{assigns: %{principal: p}} = conn, %{"id" => id}) do
    if stewards?(conn, id) do
      {since, _to} = Period.range(:month, Clock.now())

      json(conn, %{
        key: Oneiroi.Gaia.key_status(p.account_id),
        purposes: Enum.map(Nisaba.purposes(), &Atom.to_string/1),
        budgets: Enum.map(Nisaba.budgets(id, :steward), &budget/1),
        spend: %{
          since: since,
          by_purpose: Enum.map(Nisaba.spend(id, :steward, :purpose, since), &spend/1),
          by_model: Enum.map(Nisaba.spend(id, :steward, :model, since), &spend/1),
          by_actor: Enum.map(Nisaba.spend(id, :steward, :actor, since), &spend/1)
        }
      })
    else
      error(conn, 404, ResidentError.new(:agathos_daimon_not_stewarded))
    end
  end

  operation(:set_budget,
    summary: "Set a budget line: a cap in dollars (null for no limit) per day, week or month",
    parameters: [id: [in: :path, type: :string], purpose: [in: :path, type: :string]],
    request_body:
      {"the line", "application/json",
       %Schema{
         type: :object,
         required: [:period],
         properties: %{
           cap: %Schema{
             type: :string,
             nullable: true,
             description: "dollars, as a decimal string"
           },
           period: %Schema{type: :string, enum: ["day", "week", "month"]}
         }
       }},
    responses: [no_content: "set"]
  )

  def set_budget(conn, %{"id" => id, "purpose" => purpose} = params) do
    cap = Map.get(params, "cap")
    cap_nanos = if is_nil(cap), do: nil, else: Money.parse_usd(cap)

    with true <- stewards?(conn, id),
         {:ok, purpose} <- purpose(purpose),
         period when not is_nil(period) <- Period.parse(Map.get(params, "period")),
         true <- is_nil(cap) or is_integer(cap_nanos),
         :ok <- Nisaba.set_budget(id, purpose, cap_nanos, period, actor(conn)) do
      send_resp(conn, 204, "")
    else
      false ->
        if stewards?(conn, id),
          do: problem(conn, 422, :cap_invalid, "cap is dollars as a decimal string, or null"),
          else: error(conn, 404, ResidentError.new(:agathos_daimon_not_stewarded))

      nil ->
        problem(conn, 422, :period_invalid, "period is day, week or month")

      {:error, %Nisaba.Error{} = e} ->
        error(conn, 422, e)

      {:error, reason} ->
        problem(conn, 422, :budget_not_set, inspect(reason))
    end
  end

  defp purpose(string) do
    case Nisaba.Purpose.parse(string) do
      nil -> {:error, Nisaba.Error.new(:nisaba_unknown_purpose, purpose: string)}
      purpose -> {:ok, purpose}
    end
  end

  defp budget(b) do
    %{
      purpose: b.purpose,
      cap: b.cap_nanos && Money.to_usd(b.cap_nanos),
      period: b.period,
      period_key: b.period_key,
      spent: Money.to_usd(b.spent_nanos),
      exceeded: b.exceeded,
      set_at: b.set_at
    }
  end

  defp spend(s), do: %{key: s.key, calls: s.calls, cost: Money.to_usd(s.cost_nanos || 0)}
end
