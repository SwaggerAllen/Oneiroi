defmodule Oneiroi.Proteus.HonchoSchemaTest do
  @moduledoc "Honcho on Oneiroi's database (proteus #17): its own schema under its own role, which reaches nothing of Oneiroi's."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Repo

  # The role render.yaml's startup option takes, inside the sandbox's
  # transaction, so nothing here outlives the test.
  defp as_honcho(sql) do
    Repo.query!("SET LOCAL ROLE oneiroi_honcho")
    Repo.query(sql)
  end

  test "the honcho schema is the role's, and a vector column is made there" do
    assert %{rows: [["oneiroi_honcho"]]} =
             Repo.query!(
               "SELECT pg_get_userbyid(nspowner)::text FROM pg_namespace WHERE nspname = 'honcho'"
             )

    assert {:ok, _} = as_honcho(~s(CREATE SCHEMA IF NOT EXISTS "honcho"))
    assert {:ok, _} = Repo.query("CREATE TABLE honcho.probe (id int, embedding vector(3))")
  end

  # Honcho's Alembic makes its tables as the login, not the role (its
  # own connect_args drop the role option), and the running app is the
  # role: without the grants it was refused its own tables on the first
  # live deploy.
  test "a table the login makes in honcho is the role's to use" do
    Repo.query!("SET LOCAL ROLE NONE")
    Repo.query!("CREATE TABLE honcho.made_by_alembic (x int)")

    assert {:ok, _} = as_honcho("INSERT INTO honcho.made_by_alembic VALUES (1)")
    assert {:ok, %{rows: [[1]]}} = Repo.query("SELECT count(*) FROM honcho.made_by_alembic")
  end

  test "the role reads no Oneiroi table" do
    assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
             as_honcho("SELECT count(*) FROM agathos_daimon_resident")
  end

  test "nor in public" do
    assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
             as_honcho("CREATE TABLE public.intruder (x int)")
  end
end
