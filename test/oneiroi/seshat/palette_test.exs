defmodule Oneiroi.Seshat.PaletteTest do
  @moduledoc """
  The server's port of the theme derivation agrees with the client's,
  which owns it (seshat#56): the fixture is written by the client's test
  (`client/src/next/theme/derive.test.ts`) from what `derive()` answers,
  and every verdict, every check's value and every token here must be
  the same.
  """
  use ExUnit.Case, async: true

  alias Oneiroi.Seshat.Palette

  @fixture Path.expand("../../fixtures/theme/derive.json", __DIR__)
  @external_resource @fixture

  test "every seed set in the client's fixture derives the same tokens, checks and verdict" do
    rows = @fixture |> File.read!() |> Jason.decode!()
    assert length(rows) >= 10

    for %{"seeds" => seeds} = row <- rows do
      derived =
        Palette.derive(%{
          ground: seeds["ground"],
          resident: seeds["resident"],
          witness: seeds["witness"]
        })

      assert derived.ok == row["ok"], "verdict for #{inspect(seeds)}"

      assert Enum.map(derived.checks, &{&1.name, &1.passed}) ==
               Enum.map(row["checks"], &{&1["name"], &1["passed"]}),
             "checks for #{inspect(seeds)}"

      for {mine, theirs} <- Enum.zip(derived.checks, row["checks"]) do
        assert_in_delta mine.value, theirs["value"], 1.0e-9, "#{mine.name} for #{inspect(seeds)}"
      end

      assert stringify(derived.tokens) == row["tokens"], "tokens for #{inspect(seeds)}"
    end
  end

  test "the default seeds pass, and the report says each check in words" do
    %{ok: true, checks: checks} = Palette.derive(Palette.default())
    report = Palette.report(checks)
    assert report =~ "text on ground 16.5:1 (needs ≥ 7:1)"
    refute report =~ "FAILS"
  end

  defp stringify(map), do: map |> Jason.encode!() |> Jason.decode!()
end
