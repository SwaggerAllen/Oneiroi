defmodule Oneiroi.Scope do
  @moduledoc """
  The tenancy scope every query runs under (conventions §12, spec §2.2).

  Three scopes: `{:resident, id}`, `{:account, id}` and `:platform`. The
  scope is set in two places that must agree: on the connection, as
  transaction-local settings the row-level policies read
  (`current_setting('oneiroi.scope')`, `oneiroi.resident_id`,
  `oneiroi.account_id`), and on the process, which is what
  `Oneiroi.Repo.prepare_query/3` checks so an unscoped read is refused
  before it reaches the database. The database is the enforcement; the
  process check is the early, legible failure.

  `:platform` is the cross-tenant scope. Every policy admits it, so a job
  that walks every resident takes it explicitly and is named in its
  system doc; the projectors take it by construction (`Oneiroi.Projection`).
  There is no scope that reads nothing and no default: a process with no
  scope set cannot query at all.
  """

  # `Oneiroi.Repo` reads this key by the same literal; see its comment.
  @key :oneiroi_scope

  @type t :: {:resident, String.t()} | {:account, String.t()} | :platform

  @doc "Runs `fun` under `scope`, in a transaction, restoring the previous scope after."
  @spec run(t(), (-> result)) :: result when result: term()
  def run(scope, fun) when is_function(fun, 0) do
    previous = Process.get(@key)
    put(scope)

    try do
      Oneiroi.Repo.transaction(fn ->
        {:ok, _} = set_on_connection(Oneiroi.Repo, scope)
        fun.()
      end)
      |> case do
        {:ok, result} -> result
        {:error, reason} -> raise "scoped transaction failed: #{inspect(reason)}"
      end
    after
      restore(previous)
    end
  end

  @doc "`run/2` under the resident's scope."
  @spec resident(String.t(), (-> result)) :: result when result: term()
  def resident(id, fun), do: run({:resident, id}, fun)

  @doc "`run/2` under the account's scope."
  @spec account(String.t(), (-> result)) :: result when result: term()
  def account(id, fun), do: run({:account, id}, fun)

  @doc "`run/2` under the platform scope: every row, by name, in a reviewed call."
  @spec platform((-> result)) :: result when result: term()
  def platform(fun), do: run(:platform, fun)

  @doc "The scope the current process holds, or `nil`."
  @spec current() :: t() | nil
  def current, do: Process.get(@key)

  @doc "Sets the process scope without a transaction (a long-lived worker's init)."
  @spec put(t()) :: :ok
  def put(scope) do
    validate!(scope)
    Process.put(@key, scope)
    :ok
  end

  @doc """
  Sets the scope on the connection for the rest of the transaction.

  `set_config(..., true)` is transaction-local, so a scope cannot outlive
  the transaction that set it, and a pooled connection returns to the pool
  with no scope at all.
  """
  @spec set_on_connection(module(), t()) :: {:ok, t()}
  def set_on_connection(repo, scope) do
    validate!(scope)
    {kind, resident, account} = settings(scope)

    repo.query!(
      "SELECT set_config('oneiroi.scope', $1, true), set_config('oneiroi.resident_id', $2, true), " <>
        "set_config('oneiroi.account_id', $3, true)",
      [kind, resident, account]
    )

    {:ok, scope}
  end

  defp settings({:resident, id}), do: {"resident", id, ""}
  defp settings({:account, id}), do: {"account", "", id}
  defp settings(:platform), do: {"platform", "", ""}

  defp restore(nil), do: Process.delete(@key)
  defp restore(scope), do: Process.put(@key, scope)

  defp validate!({:resident, id}) when is_binary(id), do: :ok
  defp validate!({:account, id}) when is_binary(id), do: :ok
  defp validate!(:platform), do: :ok
  defp validate!(other), do: raise(ArgumentError, "not a scope: #{inspect(other)}")
end
