defmodule Oneiroi.Migration do
  @moduledoc """
  The migration helpers every projection table is created with
  (conventions §6, §12), and the shape the `tables` lint reads:

      import Oneiroi.Migration

      projection :resident_resident, scope: :resident do
        add :id, :binary_id, primary_key: true
        add :slug, :string, null: false
      end

  `projection/3` creates the table with its scope column (`resident_id` or
  `account_id`, both for `scope: :both`), enables and **forces** row-level
  security, so the table's owner is subject to the policies too, and
  writes the one policy: the platform scope sees every row, a resident or
  account scope sees its own. Every table a system creates goes through
  it; the lint reports a bare `create table` as a table with no tenancy.
  """

  defmacro projection(name, opts, do: block) do
    scope = Keyword.fetch!(opts, :scope)

    quote do
      table = unquote(name)

      Ecto.Migration.create Ecto.Migration.table(table, primary_key: false) do
        unquote(block)
        Oneiroi.Migration.scope_columns(unquote(scope))
      end

      for statement <- Oneiroi.Migration.policy_statements(table, unquote(scope)) do
        Ecto.Migration.execute(statement)
      end
    end
  end

  @doc false
  defmacro scope_columns(scope) do
    quote do
      case unquote(scope) do
        :resident ->
          Ecto.Migration.add(:resident_id, :binary_id, null: false)

        :account ->
          Ecto.Migration.add(:account_id, :binary_id, null: false)

        :both ->
          Ecto.Migration.add(:resident_id, :binary_id, null: false)
          Ecto.Migration.add(:account_id, :binary_id, null: false)
      end
    end
  end

  @doc "The row-level security statements for a table under `scope`, in order."
  @spec policy_statements(atom(), :resident | :account | :both) :: [String.t()]
  def policy_statements(table, scope) do
    [
      ~s|ALTER TABLE "#{table}" ENABLE ROW LEVEL SECURITY|,
      ~s|ALTER TABLE "#{table}" FORCE ROW LEVEL SECURITY|,
      ~s|CREATE POLICY "#{table}_scope" ON "#{table}" FOR ALL | <>
        ~s|USING (#{predicate(scope)}) WITH CHECK (#{predicate(scope)})|
    ]
  end

  defp predicate(:resident), do: "#{platform()} OR #{resident()}"
  defp predicate(:account), do: "#{platform()} OR #{account()}"
  defp predicate(:both), do: "#{platform()} OR #{resident()} OR #{account()}"

  defp platform, do: "current_setting('oneiroi.scope', true) = 'platform'"

  defp resident,
    do: "resident_id = NULLIF(current_setting('oneiroi.resident_id', true), '')::uuid"

  defp account,
    do: "account_id = NULLIF(current_setting('oneiroi.account_id', true), '')::uuid"
end
