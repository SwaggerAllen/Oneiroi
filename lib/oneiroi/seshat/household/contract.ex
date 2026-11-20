defmodule Oneiroi.Seshat.Household.Contract do
  @moduledoc """
  The contract (gaia#27, #28; seshat#63): proposed, signed and read,
  and a ballot's close, each rendering `CONTRACT.md`.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files

  @platform %{name: "Oneiroi", email: "oneiroi@records.invalid"}

  @doc false
  def propose_contract(%Actor{} = actor, prose, note, bundle \\ nil) do
    with {:ok, household_id} <- Core.household(actor),
         :ok <- Gaia.propose_household_contract(household_id, prose, note, actor, bundle),
         do:
           rendered(
             household_id,
             "Contract: version 1 proposed",
             Core.author(household_id, actor)
           )
  end

  @doc false
  def sign_contract(%Actor{} = actor) do
    with {:ok, household_id} <- Core.household(actor),
         %{in_force: %{version: v}} <- Gaia.household_contract(household_id) do
      with :ok <- Gaia.sign_household_contract(household_id, v, actor),
           do:
             rendered(
               household_id,
               "Contract: signed at version #{v}",
               Core.author(household_id, actor)
             )
    else
      %{in_force: nil} ->
        {:error, Error.new(:seshat_household_invalid, :seshat_household_sign_no_contract)}

      other ->
        other
    end
  end

  @doc false
  def contract(%Actor{} = actor) do
    with {:ok, household_id} <- Core.household(actor),
         {:ok, _dir} <- Core.provision(household_id),
         do: {:ok, Gaia.household_contract(household_id)}
  end

  defp rendered(household_id, message, by) do
    Files.locked(household_id, fn view ->
      with {:ok, _} <- Files.commit(view, Core.render_contract(view, household_id), message, by),
           do: {:ok, Gaia.household_contract(household_id)}
    end)
  end

  @doc false
  def close_ballot(household_id, ballot, %Actor{} = actor) do
    with {:ok, outcome} when is_map(outcome) <-
           Gaia.close_household_ballot(household_id, ballot, actor),
         {:ok, _view} <- Core.provision(household_id) do
      thread =
        Enum.find_value(
          Gaia.household_contract(household_id).ballots,
          &(&1.number == ballot && &1.thread)
        )

      Files.locked(household_id, fn view ->
        write_outcome(household_id, view, thread, ballot, outcome)
      end)
    end
  end

  defp write_outcome(household_id, view, thread, ballot, outcome) do
    number = Files.next_reply(view, thread)
    path = Files.reply_path(thread, number, "oneiroi")

    carried =
      if outcome.version,
        do: " The bundle is the household contract's version #{outcome.version}.",
        else: ""

    meta = [
      {"by", "Oneiroi"},
      {"by_kind", "platform"},
      {"at", Files.iso(Clock.now())},
      {"reply", Integer.to_string(number)},
      {"outcome", if(outcome.passed, do: "carried", else: "failed")}
    ]

    changes = [
      {:create, path,
       Files.render(meta, "Ballot ##{ballot} closed. #{outcome.outcome}" <> carried)}
      | Core.render_contract(view, household_id)
    ]

    with {:ok, _} <- Files.commit(view, changes, "Ballot ##{ballot} closed", @platform),
         do: {:ok, outcome}
  end
end
