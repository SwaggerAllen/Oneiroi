defmodule Oneiroi.Xenia.Substack.Fake do
  @moduledoc """
  The in-memory Substack port (conventions §9): a profile, each
  account's items and each item's text, set by a test. `items/2` keeps
  the `since` it was asked with, so a test can say what was handed
  forward.
  """
  @behaviour Oneiroi.Xenia.Substack

  alias Oneiroi.Xenia.Error

  @key {__MODULE__, :state}

  @doc "Sets the profile: its id and accounts, and the count it claims is visible (the list's length by default)."
  def put_profile(id, accounts, visible \\ nil),
    do:
      update(
        &Map.put(&1, :profile, %{id: id, accounts: accounts, visible: visible || length(accounts)})
      )

  @doc "Sets an account's items, newest or not; `items/2` filters by `since` and sorts."
  def put_items(account_key, items), do: update(&put_in(&1, [:items, account_key], items))

  @doc "Sets an item's whole text."
  def put_text(item_key, text), do: update(&put_in(&1, [:texts, item_key], text))

  @doc "The `since` each account was asked with, in order."
  def asked, do: state().asked |> Enum.reverse()

  @doc "Forgets everything."
  def clear, do: :persistent_term.erase(@key)

  @impl true
  def profile(_handle) do
    case state().profile do
      nil -> {:error, Error.new(:xenia_substack_failed, :xenia_substack_fake_no_profile)}
      profile -> {:ok, profile}
    end
  end

  @impl true
  def items(account, since) do
    update(&Map.update!(&1, :asked, fn asked -> [{account.key, since} | asked] end))

    {:ok,
     state().items
     |> Map.get(account.key, [])
     |> Enum.filter(&(DateTime.compare(&1.at, since) == :gt))
     |> Enum.sort_by(& &1.at, {:desc, DateTime})}
  end

  @impl true
  def text(%{key: key}) do
    case Map.fetch(state().texts, key) do
      {:ok, text} -> {:ok, text}
      :error -> {:ok, "The whole of #{key}."}
    end
  end

  defp state,
    do: :persistent_term.get(@key, %{profile: nil, items: %{}, texts: %{}, asked: []})

  defp update(fun), do: :persistent_term.put(@key, fun.(state()))
end
