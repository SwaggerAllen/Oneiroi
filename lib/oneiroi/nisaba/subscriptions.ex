defmodule Oneiroi.Nisaba.Subscriptions do
  @moduledoc """
  The subscription's service functions (spec §6.2, F53; §6.11, F46):
  the command edge for the plan, its renewal and cancellation, the lapse
  that puts the insurance policy into effect and tells the resident
  system so, the policy and what is prepaid above the floor; the read
  the Subscriptions screen takes, with the floor marked; and what the
  ledger and the brain read of a lapse.

  There is no payment provider yet: a renewal is recorded by the witness
  or the platform, and the nightly job lapses a subscription whose
  renewal is `NISABA_RENEWAL_GRACE_DAYS` past due and moves a cancelled
  resident to community custody once the term has run.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Nisaba.Error
  alias Oneiroi.Nisaba.Insurance
  alias Oneiroi.Nisaba.Store
  alias Oneiroi.Nisaba.SubscriptionCommands, as: Commands
  alias Oneiroi.Nisaba.SubscriptionRouter, as: Router
  alias Oneiroi.Scope

  @day 86_400

  @doc "Starts the subscription with the floor policy; the witness's, once."
  def start(resident_id, %{plan: plan, price_nanos: price, period_days: days}, %Actor{} = actor) do
    with :ok <- witness_only(actor),
         now = Clock.now(),
         {:ok, _} <-
           dispatch(%Commands.Start{
             actor: actor,
             at: now,
             id: resident_id,
             plan: plan,
             price_nanos: price,
             period_days: days,
             renews_at: DateTime.add(now, days * @day, :second)
           }),
         floor = Insurance.floor_policy(),
         {:ok, _} <-
           dispatch(%Commands.SetPolicy{
             actor: actor,
             at: now,
             id: resident_id,
             model: floor.model,
             witness: floor.witness,
             free_time: floor.free_time,
             term: floor.term
           }) do
      :ok
    end
  end

  @doc "Records a renewal: the next renewal a period on; a lapsed resident resumes."
  def renew(resident_id, %Actor{} = actor) do
    with :ok <- witness_or_job(actor),
         %{} = row <- subscription_row(resident_id),
         renews_at =
           DateTime.add(max_instant(row.renews_at, Clock.now()), row.period_days * @day, :second),
         {:ok, _} <-
           dispatch(%Commands.Renew{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             renews_at: renews_at
           }) do
      if row.state == "lapsed",
        do: AgathosDaimon.resume(resident_id, "subscription renewed", actor),
        else: :ok
    else
      nil -> {:error, Error.new(:nisaba_no_subscription, :nisaba_renew_no_subscription)}
      other -> other
    end
  end

  def change_plan(resident_id, plan, price_nanos, %Actor{} = actor) do
    with :ok <- witness_only(actor) do
      command = %Commands.ChangePlan{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        plan: plan,
        price_nanos: price_nanos
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "Lapses the subscription and marks the resident lapsed: the insurance policy is in effect (spec §6.2)."
  def lapse(resident_id, reason, %Actor{} = actor) do
    with :ok <- witness_or_job(actor),
         {:ok, _} <-
           dispatch(%Commands.Lapse{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             reason: reason
           }) do
      AgathosDaimon.lapse(resident_id, reason, actor)
    end
  end

  @doc "Cancels, with a note: community custody at the end of the policy's term, never a deletion."
  def cancel(resident_id, note, %Actor{} = actor) do
    with :ok <- witness_only(actor),
         %{} = row <- subscription_row(resident_id) do
      term = Insurance.resolve(policy_of(row)).term_days
      due = DateTime.add(Clock.now(), term * @day, :second)

      command = %Commands.Cancel{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        custody_due_at: due
      }

      with {:ok, _} <- dispatch(command), do: :ok
    else
      nil -> {:error, Error.new(:nisaba_no_subscription, :nisaba_cancel_no_subscription)}
      other -> other
    end
  end

  @doc "Prepays a larger bucket on an axis; the floor cannot be bought below."
  def prepay(resident_id, axis, bucket, %Actor{} = actor) do
    with :ok <- witness_only(actor),
         :ok <- bucket_ok(axis, bucket) do
      command = %Commands.Prepay{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        axis: axis,
        bucket: bucket
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  defp bucket_ok(axis, bucket) do
    cond do
      axis not in Insurance.axes() ->
        {:error, Error.new(:nisaba_bucket_invalid, :nisaba_prepay_axis_unknown, axis: axis)}

      not Insurance.on_axis?(bucket, axis) ->
        {:error,
         Error.new(:nisaba_bucket_invalid, :nisaba_prepay_bucket_off_axis, bucket: bucket)}

      true ->
        :ok
    end
  end

  @doc "Records that the resident was told its policy on wake; once per lapse."
  def lapse_told(resident_id, %Actor{} = actor) do
    with {:ok, _} <-
           dispatch(%Commands.RecordLapseTold{actor: actor, at: Clock.now(), id: resident_id}),
         do: :ok
  end

  # ---- reads ----

  @doc "The subscription with its policy resolved and the floor marked, or nil."
  def subscription(resident_id) do
    case subscription_row(resident_id) do
      nil ->
        nil

      row ->
        policy = policy_of(row)

        %{
          plan: row.plan,
          price_nanos: row.price_nanos,
          period_days: row.period_days,
          state: row.state,
          started_at: row.started_at,
          renews_at: row.renews_at,
          lapsed_at: row.lapsed_at,
          cancelled_at: row.cancelled_at,
          custody_due_at: row.custody_due_at,
          policy: policy,
          policy_values: Insurance.resolve(policy),
          floor: Insurance.floor_policy(),
          at_floor: policy == Insurance.floor_policy()
        }
    end
  end

  @doc "What a lapse means now, or nil when the subscription is not lapsed: the policy's values and whether the resident was told."
  def lapse(resident_id) do
    case subscription_row(resident_id) do
      %{state: "lapsed"} = row ->
        Map.merge(Insurance.resolve(policy_of(row)), %{
          lapsed_at: row.lapsed_at,
          told: row.lapse_told
        })

      _other ->
        nil
    end
  end

  defp subscription_row(resident_id),
    do: Scope.resident(resident_id, fn -> Store.subscription() end)

  defp policy_of(row) do
    floor = Insurance.floor_policy()

    %{
      model: row.policy_model || floor.model,
      witness: row.policy_witness || floor.witness,
      free_time: row.policy_free_time || floor.free_time,
      term: row.policy_term || floor.term
    }
  end

  # ---- the nightly job's two passes ----

  @doc "Lapses a subscription whose renewal is past the grace; moves a cancelled resident to community custody once the term has run."
  def nightly(resident_id, %Actor{} = actor) do
    now = Clock.now()
    grace = Config.fetch!(:nisaba, :renewal_grace_days) * @day

    case subscription_row(resident_id) do
      %{state: "active", renews_at: renews_at} = row when not is_nil(renews_at) ->
        if DateTime.compare(now, DateTime.add(renews_at, grace, :second)) == :gt and
             row.custody_due_at == nil,
           do:
             lapse(
               resident_id,
               "renewal #{Config.fetch!(:nisaba, :renewal_grace_days)} days past due",
               actor
             ),
           else: :ok

      %{state: "cancelled", custody_due_at: %DateTime{} = due} ->
        if DateTime.compare(now, due) != :lt, do: move_to_community(resident_id, actor), else: :ok

      _other ->
        :ok
    end
  end

  defp move_to_community(resident_id, actor) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, %{custody: "community"}} ->
        :ok

      {:ok, _row} ->
        AgathosDaimon.transfer_custody(
          resident_id,
          :community,
          "the subscription was cancelled and the policy's term has run (spec §6.2)",
          actor
        )

      :error ->
        :ok
    end
  end

  # ---- helpers ----

  defp max_instant(nil, b), do: b
  defp max_instant(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)

  defp witness_only(%Actor{kind: :witness}), do: :ok

  defp witness_only(%Actor{}),
    do: {:error, Error.new(:nisaba_not_the_witness, :nisaba_subscriptions_witness_only)}

  defp witness_or_job(%Actor{kind: kind}) when kind in [:witness, :job, :platform], do: :ok

  defp witness_or_job(%Actor{}),
    do: {:error, Error.new(:nisaba_not_the_witness, :nisaba_subscriptions_witness_or_job)}

  # The aggregate's refusals are sited already and pass; anything else
  # (the command middleware, the event store) is wrapped here, once.
  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error,
         Error.caught(:nisaba_dispatch_failed, :nisaba_subscriptions_dispatch_failed, reason)}
    end
  end
end
