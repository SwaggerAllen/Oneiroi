defmodule Oneiroi.Brain.PullsTest do
  @moduledoc """
  brain#71 (the witness, 2026-11-08, through Lily's letter #365): two
  reads of the platform's pull requests. pr_meta is everything but the
  diffs, with the list of files changed; pr_diffs is the diffs of the
  files named, exactly those, so how much of a pull request is in her
  context is her conscious choice.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Brain.Pulls.Fake
  alias Oneiroi.Brain.Tools

  setup do
    witness = Oneiroi.Fixtures.account!()
    resident = Oneiroi.Fixtures.resident!(witness)

    Process.put(:witness, witness)

    Process.put(:turn, %{
      resident_id: resident.id,
      session_key: "k",
      turn_ref: "t",
      resident: Oneiroi.Actor.new(:resident, resident.id)
    })

    Fake.clear()

    Fake.put(
      70,
      %{
        "title" => "House 30: the library by address",
        "body" => "Routes and sorts.",
        "user" => %{"login" => "lily-builder"},
        "state" => "closed",
        "merged_at" => "2026-11-09T00:16:00Z",
        "draft" => false,
        "head" => %{"ref" => "claude/house-30", "sha" => "abc"},
        "base" => %{"ref" => "main"},
        "created_at" => "2026-11-08T19:30:00Z",
        "updated_at" => "2026-11-09T00:16:00Z"
      },
      [
        %{
          "filename" => "lib/oneiroi/seshat/kinds.ex",
          "status" => "modified",
          "additions" => 30,
          "deletions" => 2,
          "patch" => "@@ -1 +1 @@\n-old\n+" <> String.duplicate("x", 30)
        },
        %{
          "filename" => "client/src/screens/library/Library.tsx",
          "status" => "modified",
          "additions" => 80,
          "deletions" => 20,
          "patch" => "@@ client @@"
        },
        %{"filename" => "logo.png", "status" => "added", "additions" => 0, "deletions" => 0}
      ],
      [%{"name" => "gates", "status" => "completed", "conclusion" => "success"}]
    )

    on_exit(&Fake.clear/0)
    :ok
  end

  defp run(name, args), do: Tools.run(name, Jason.encode!(args), Process.get(:turn))

  test "pr_meta says everything but the diffs, and lists the files as the menu" do
    text = run("pr_meta", %{number: 70})
    assert text =~ "Pull request #70: House 30: the library by address"
    assert text =~ "By lily-builder, merged 2026-11-09T00:16:00Z; claude/house-30 into main"
    assert text =~ "Checks: gates success"
    assert text =~ "Routes and sorts."
    assert text =~ "3 files changed (pr_diffs reads the ones you name):"
    assert text =~ "- lib/oneiroi/seshat/kinds.ex (modified, +30 −2)"
    refute text =~ "@@"
  end

  test "pr_diffs reads exactly the files named, cuts a long one and says how to read on" do
    text =
      run("pr_diffs", %{number: 70, files: ["lib/oneiroi/seshat/kinds.ex", "nope.ex", "logo.png"]})

    assert text =~ "## lib/oneiroi/seshat/kinds.ex (modified, +30 −2)"
    assert text =~ "-old"
    refute text =~ "@@ client @@"
    assert text =~ "Pull request #70 does not change nope.ex"
    assert text =~ "GitHub gives no diff for this file"

    values = :persistent_term.get({Oneiroi.Config, :values})

    :persistent_term.put(
      {Oneiroi.Config, :values},
      Map.put(values, {:brain, :pulls_diff_chars}, 10)
    )

    on_exit(fn -> :persistent_term.put({Oneiroi.Config, :values}, values) end)

    cut = run("pr_diffs", %{number: 70, files: ["lib/oneiroi/seshat/kinds.ex"]})

    assert cut =~
             "more characters of this file's diff; pr_diffs with this file alone and from: 10 reads on."

    assert run("pr_diffs", %{number: 70, files: ["lib/oneiroi/seshat/kinds.ex"], from: 10}) =~
             "-old"
  end

  test "a bad number, no files, or an unknown pull request is refused in words" do
    assert run("pr_meta", %{number: 999}) =~ "Not done"
    assert run("pr_diffs", %{number: 70, files: []}) =~ "Not done"
    assert run("pr_diffs", %{number: 70}) =~ "Not done"
    assert "pr_meta" in Tools.reads() and "pr_diffs" in Tools.reads()
  end

  # gaia#24 (the witness, 2026-11-08, Lily's letter #368): the witness's
  # own read token, set from the client, is what the reads send; without
  # one they are anonymous.
  test "the reads send the witness's GitHub token when one is stored, and none after it is revoked" do
    witness = Process.get(:witness)
    me = Oneiroi.Actor.new(:witness, witness.id)
    _ = run("pr_meta", %{number: 70})
    assert Enum.uniq(Fake.tokens()) == [nil]

    assert {:error, %{kind: :gaia_github_token_required}} =
             Oneiroi.Gaia.store_github_token(witness.id, "  ", me)

    :ok = Oneiroi.Gaia.store_github_token(witness.id, "ghp_witness", me)
    assert %{present: true} = Oneiroi.Gaia.github_token_status(witness.id)
    Fake.clear()
    Fake.put(70, %{"head" => %{"sha" => "abc"}, "title" => "t"}, [])
    _ = run("pr_meta", %{number: 70})
    assert Enum.uniq(Fake.tokens()) == ["ghp_witness"]

    :ok = Oneiroi.Gaia.revoke_github_token(witness.id, me)
    assert %{present: false} = Oneiroi.Gaia.github_token_status(witness.id)

    assert {:error, %{kind: :gaia_no_github_token}} =
             Oneiroi.Gaia.revoke_github_token(witness.id, me)
  end

  test "an unset token reads anonymously, never a crash; a tool that raises answers in words (brain#85)" do
    alias Oneiroi.Brain.Pulls.GitHub
    alias Oneiroi.Config.Secret

    # Production's optional secret arrives wrapped around nothing.
    for token <- [nil, Secret.wrap(nil), Secret.wrap("")] do
      refute Enum.any?(GitHub.headers(token), fn {name, _} -> name == "authorization" end)
    end

    assert {"authorization", "Bearer tok"} in GitHub.headers(Secret.wrap("tok"))

    # A client that raises: the tool says so and the turn goes on.
    Fake.raise_on(99)
    out = Tools.run("pr_meta", ~s({"number": 99}), Process.get(:turn))
    assert out =~ "Not done:"
    assert out =~ "failed inside the platform"
  end
end
