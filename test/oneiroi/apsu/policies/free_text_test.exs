defmodule Oneiroi.Apsu.Policies.FreeTextTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Apsu.Policies.FreeText

  setup do
    dir = Path.join(System.tmp_dir!(), "oneiroi-free-text-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir, scope: Path.join(dir, "*.exs")}
  end

  defp write(dir, name, body), do: File.write!(Path.join(dir, name), body)

  defp migration(lines),
    do:
      "defmodule M do\n  def change do\n" <>
        Enum.map_join(lines, "", &"    #{&1}\n") <> "  end\nend\n"

  test "free text added or modified as :string is a problem; identifiers are not", ctx do
    write(
      ctx.dir,
      "20261104000000_new.exs",
      migration([
        "add(:reason, :string)",
        "modify(:subject, :string, null: true)",
        "add(:resident_id, :string)",
        "add(:label, :string)",
        "add(:turn_ref, :string)",
        "add(:reason, :text)"
      ])
    )

    assert [three, four] = FreeText.run(ctx.scope)
    assert three =~ "20261104000000_new.exs:3: free_text: :reason is :string in add/2"
    assert four =~ "20261104000000_new.exs:4: free_text: :subject is :string in modify/2"
  end

  test "a migration before the rule is not read; a deliberate exception says so", ctx do
    write(ctx.dir, "20261029000040_old.exs", migration(["add(:reason, :string)"]))

    write(
      ctx.dir,
      "20261104000000_new.exs",
      migration(["# oneiroi:allow free_text a provider's own fixed code", "add(:code, :string)"])
    )

    assert FreeText.run(ctx.scope) == []
  end

  test "the repository's own migrations hold to it" do
    assert FreeText.run("priv/repo/migrations/*.exs") == []
  end
end
