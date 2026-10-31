defmodule Oneiroi.Apsu.Policies.ProjectorScopeTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Apsu.Policies.ProjectorScope

  setup do
    dir = Path.join(System.tmp_dir!(), "oneiroi-pscope-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir, scope: Path.join(dir, "*.ex")}
  end

  defp write(dir, body), do: File.write!(Path.join(dir, "p.ex"), body)

  test "a query naming its resident, its account or the row's own id is not a problem", ctx do
    write(ctx.dir, """
    defmodule P do
      def a(e), do: from(p in Prediction, where: p.resident_id == ^e.id and p.number == ^e.number)
      def b(e), do: from(s in Session, where: s.account_id == ^e.id)
      def c(e), do: from(r in Resident, where: r.id == ^e.id)
    end
    """)

    assert ProjectorScope.run(ctx.scope) == []
  end

  test "a query keyed on a per-resident number alone is", ctx do
    write(ctx.dir, """
    defmodule P do
      def a(e), do: from(p in Prediction, where: p.number == ^e.number)
    end
    """)

    assert [problem] = ProjectorScope.run(ctx.scope)
    assert problem =~ "p.ex:2: projector_scope: a query on Prediction keys on no tenant"
  end

  test "another binding's tenant does not count, and a query with no where is reported", ctx do
    write(ctx.dir, """
    defmodule P do
      def a(e, q), do: from(p in Prediction, where: q.resident_id == ^e.id and p.number == 1)
      def b, do: from(p in Prediction, select: p.number)
    end
    """)

    assert [two, three] = ProjectorScope.run(ctx.scope)
    assert two =~ "p.ex:2: projector_scope: a query on Prediction keys on no tenant"
    assert three =~ "p.ex:3: projector_scope: a query on Prediction has no where: at all"
  end

  test "the escape covers a row unique across the store, and an idle one is reported", ctx do
    write(ctx.dir, """
    defmodule P do
      # oneiroi:allow projector_scope (a hash of a random token)
      def a(h), do: from(t in Token, where: t.hash == ^h)
      # oneiroi:allow projector_scope
      def b(e), do: from(t in Token, where: t.account_id == ^e.id)
    end
    """)

    assert [idle] = ProjectorScope.run(ctx.scope)
    assert idle =~ "p.ex:4: oneiroi:allow projector_scope excuses nothing"
  end
end
