defmodule Oneiroi.Nisaba.Subscription do
  @moduledoc """
  The subscription aggregate on `subscription-<resident_id>` (spec
  §6.2, F53). Pure: instants and bucket ids arrive on the command; the
  bucket catalogue is checked at the command edge. It holds the state
  (active, lapsed, cancelled), the policy, and whether the lapse was
  told, so a lapse is told once and a cancellation is final.
  """

  alias Oneiroi.Nisaba.Events.Subscription, as: Events
  alias Oneiroi.Nisaba.SubscriptionCommands, as: Commands

  defstruct [:id, :state, :plan, policy: nil, lapse_told: true]

  @plan_limit 60

  def execute(%__MODULE__{state: nil}, %Commands.Start{} = c) do
    cond do
      not plan_ok?(c.plan) -> {:error, :plan_invalid}
      not price_ok?(c.price_nanos) -> {:error, :price_invalid}
      not (is_integer(c.period_days) and c.period_days > 0) -> {:error, :period_invalid}
      not match?(%DateTime{}, c.renews_at) -> {:error, :period_invalid}
      true -> started(c)
    end
  end

  def execute(%__MODULE__{}, %Commands.Start{}), do: []

  def execute(%__MODULE__{state: nil}, _command), do: {:error, :not_started}
  def execute(%__MODULE__{state: :cancelled}, %Commands.RecordLapseTold{} = c), do: told(c)
  def execute(%__MODULE__{state: :cancelled}, _command), do: {:error, :cancelled}

  def execute(%__MODULE__{}, %Commands.Renew{} = c) do
    if match?(%DateTime{}, c.renews_at),
      do: %Events.Renewed{actor: c.actor, at: c.at, id: c.id, renews_at: c.renews_at},
      else: {:error, :period_invalid}
  end

  def execute(%__MODULE__{plan: plan}, %Commands.ChangePlan{} = c) do
    cond do
      not plan_ok?(c.plan) ->
        {:error, :plan_invalid}

      not price_ok?(c.price_nanos) ->
        {:error, :price_invalid}

      plan == {c.plan, c.price_nanos} ->
        []

      true ->
        %Events.PlanChanged{
          actor: c.actor,
          at: c.at,
          id: c.id,
          plan: c.plan,
          price_nanos: c.price_nanos
        }
    end
  end

  def execute(%__MODULE__{state: :lapsed}, %Commands.Lapse{}), do: []

  def execute(%__MODULE__{}, %Commands.Lapse{} = c),
    do: %Events.Lapsed{actor: c.actor, at: c.at, id: c.id, reason: c.reason}

  def execute(%__MODULE__{}, %Commands.Cancel{} = c) do
    if match?(%DateTime{}, c.custody_due_at),
      do: %Events.Cancelled{
        actor: c.actor,
        at: c.at,
        note: c.note,
        id: c.id,
        custody_due_at: c.custody_due_at
      },
      else: {:error, :period_invalid}
  end

  def execute(%__MODULE__{policy: policy}, %Commands.SetPolicy{} = c) do
    wanted = %{model: c.model, witness: c.witness, free_time: c.free_time, term: c.term}

    if policy == wanted,
      do: [],
      else: %Events.PolicySet{
        actor: c.actor,
        at: c.at,
        id: c.id,
        model: c.model,
        witness: c.witness,
        free_time: c.free_time,
        term: c.term
      }
  end

  def execute(%__MODULE__{policy: policy}, %Commands.Prepay{} = c) do
    axis = c.axis && String.to_existing_atom(c.axis)

    if policy && Map.get(policy, axis) == c.bucket,
      do: [],
      else: %Events.Prepaid{actor: c.actor, at: c.at, id: c.id, axis: c.axis, bucket: c.bucket}
  end

  def execute(%__MODULE__{}, %Commands.RecordLapseTold{} = c), do: told(c)

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.Started{} = e),
    do: %{s | id: e.id, state: :active, plan: {e.plan, e.price_nanos}}

  def apply(%__MODULE__{} = s, %Events.Renewed{}), do: %{s | state: :active, lapse_told: true}

  def apply(%__MODULE__{} = s, %Events.PlanChanged{} = e),
    do: %{s | plan: {e.plan, e.price_nanos}}

  def apply(%__MODULE__{} = s, %Events.Lapsed{}), do: %{s | state: :lapsed, lapse_told: false}
  def apply(%__MODULE__{} = s, %Events.Cancelled{}), do: %{s | state: :cancelled}

  def apply(%__MODULE__{} = s, %Events.PolicySet{} = e),
    do: %{s | policy: %{model: e.model, witness: e.witness, free_time: e.free_time, term: e.term}}

  def apply(%__MODULE__{} = s, %Events.Prepaid{} = e),
    do: %{s | policy: Map.put(s.policy || %{}, String.to_existing_atom(e.axis), e.bucket)}

  def apply(%__MODULE__{} = s, %Events.LapseTold{}), do: %{s | lapse_told: true}

  # ---- helpers ----

  defp started(c) do
    %Events.Started{
      actor: c.actor,
      at: c.at,
      id: c.id,
      plan: c.plan,
      price_nanos: c.price_nanos,
      period_days: c.period_days,
      renews_at: c.renews_at
    }
  end

  defp told(c), do: %Events.LapseTold{actor: c.actor, at: c.at, id: c.id}

  defp plan_ok?(plan),
    do: is_binary(plan) and String.trim(plan) != "" and String.length(plan) <= @plan_limit

  defp price_ok?(nanos), do: is_integer(nanos) and nanos >= 0
end
