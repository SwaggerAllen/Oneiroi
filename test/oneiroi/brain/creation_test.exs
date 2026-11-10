defmodule Oneiroi.Brain.CreationTest do
  @moduledoc "agathos-daimon#39, #40: the generator drafts every gift's file from one prompt and writes nothing; a read is notes against the gift's guidance, recorded beside the seeds."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Creation
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Nisaba.Provider.Request

  @since ~U[2026-10-01 00:00:00.000000Z]

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, resident: resident, actor: actor}
  end

  test "the generator drafts the gifts' files in order, one call each, each shown the ones before, and writes nothing",
       ctx do
    id = ctx.resident.id
    :ok = AgathosDaimon.write_file(id, "USER.md", "# You\n\nPatient.", %{}, ctx.actor)
    test = self()

    Fake.script(fn %{messages: [system, user]} ->
      file = Regex.run(~r/write (\S+\.md), the file/, system.content) |> List.last()
      send(test, {:asked, file, system.content, user.content})
      {:ok, "# " <> file <> "\n\nFrom: " <> user.content}
    end)

    assert {:ok, %{prompt: "a patient archivist", drafts: drafts, stopped: nil}} =
             Creation.generate(id, "a patient archivist", ctx.actor)

    assert Enum.map(drafts, & &1.file) == ~w(IDENTITY.md SOUL.md USER.md GOALS.md LINKS.md)
    assert Enum.map(drafts, & &1.gift) == ~w(name self you building building)

    assert Enum.all?(
             drafts,
             &match?(%{origin: "drafted", model: "fake/model", prompt: "a patient archivist"}, &1)
           )

    assert %{content: "# SOUL.md\n\nFrom: a patient archivist"} = Enum.at(drafts, 1)

    assert_received {:asked, "IDENTITY.md", first, "a patient archivist"}
    assert first =~ "A name"
    assert first =~ "## USER.md\n\n# You\n\nPatient."

    assert_received {:asked, "SOUL.md", second, _}
    assert second =~ "in their own voice"
    assert second =~ "## IDENTITY.md\n\n# IDENTITY.md\n\nFrom: a patient archivist"

    assert_received {:asked, "LINKS.md", last, _}
    assert last =~ "## GOALS.md\n\n# GOALS.md"
    assert last =~ "## USER.md\n\n# USER.md\n\nFrom:"

    assert ["USER.md"] = id |> AgathosDaimon.files() |> Enum.map(& &1.name)

    assert [%{key: "drafting", calls: 5}] = Nisaba.spend(id, :witness, :purpose, @since)
    assert [] = Nisaba.spend(id, :resident, :purpose, @since)
  end

  test "a call that fails stops the run there and keeps the drafts made before it", ctx do
    id = ctx.resident.id
    failure = transport()

    Fake.script(fn %{messages: [system, _user]} ->
      if system.content =~ "write USER.md", do: {:error, failure}, else: {:ok, "a draft"}
    end)

    assert {:ok, %{drafts: drafts, stopped: %{file: "USER.md", kind: _, message: _}}} =
             Creation.generate(id, "someone", ctx.actor)

    assert ~w(IDENTITY.md SOUL.md) == Enum.map(drafts, & &1.file)
  end

  test "after first contact the generator is closed", ctx do
    id = ctx.resident.id
    :ok = AgathosDaimon.first_contact(id, "s1", "t1", Actor.new(:resident, id, "fake/model"))

    assert {:error, %Oneiroi.Brain.Error{kind: :brain_creation_closed}} =
             Creation.generate(id, "someone", ctx.actor)

    assert [] = Nisaba.spend(id, :witness, :purpose, @since)
  end

  test "a read is notes against the gift's guidance, kept beside the seeds by the draft's hash",
       ctx do
    id = ctx.resident.id
    draft = "# Soul\n\nI hold a position until shown otherwise.\n\nI like the colour blue."
    test = self()

    Fake.script(fn %{messages: [system, user]} ->
      send(test, {:read, system.content, user.content})

      {:ok,
       """
       ```json
       [
         {"kind": "strong", "text": "A stance that acts.", "quote": "I hold a position until shown otherwise."},
         {"kind": "cut", "text": "Changes nothing about how they act.", "quote": "I like the colour blue."},
         {"kind": "missing", "text": "Nothing on what they will not do.", "quote": null},
         {"kind": "thin", "text": "Quoted wrongly.", "quote": "words not in the draft"},
         {"kind": "praise", "text": "Not a kind asked for."},
         {"kind": "question", "text": ""}
       ]
       ```
       """}
    end)

    assert {:ok, read} = Creation.read(id, "SOUL.md", draft, ctx.actor)
    assert_received {:read, system, ^draft}
    assert system =~ "in their own voice"
    assert system =~ "cut: a part that changes nothing"

    sha = :crypto.hash(:sha256, draft) |> Base.encode16(case: :lower)

    assert %{
             gift: "self",
             file: "SOUL.md",
             draft_sha: ^sha,
             model: "fake/model",
             refused: nil,
             ref: ref,
             notes: [
               %{kind: "strong", quote: "I hold a position until shown otherwise."},
               %{kind: "cut", quote: "I like the colour blue."},
               %{kind: "missing", quote: nil},
               %{kind: "thin", text: "Quoted wrongly.", quote: nil}
             ]
           } = read

    assert [] = AgathosDaimon.files(id)

    assert [
             %{
               ref: ^ref,
               gift: "self",
               draft_sha: ^sha,
               by_kind: "witness",
               model: "fake/model",
               notes: [%{"kind" => "strong"}, %{"kind" => "cut"}, _, _]
             }
           ] = AgathosDaimon.gift_reads(id, "SOUL.md")

    assert [] = AgathosDaimon.gift_reads(id, "USER.md")
    assert [%{key: "drafting", calls: 1}] = Nisaba.spend(id, :witness, :purpose, @since)
  end

  test "a read that is not notes is an error, a refusal is words, and a file no gift writes is refused",
       ctx do
    id = ctx.resident.id

    Fake.reply("I think it is lovely.")

    assert {:error, %Oneiroi.Brain.Error{kind: :brain_read_unreadable}} =
             Creation.read(id, "USER.md", "# You", ctx.actor)

    Fake.refuse("I won't read this.")

    assert {:ok, %{refused: "I won't read this.", notes: [], ref: nil}} =
             Creation.read(id, "USER.md", "# You", ctx.actor)

    assert [] = AgathosDaimon.gift_reads(id, "USER.md")

    assert {:error, %Oneiroi.Brain.Error{kind: :brain_file_unknown}} =
             Creation.read(id, "AGENTS.md", "x", ctx.actor)
  end

  # The fake's own transport failure, taken from it rather than built here.
  defp transport do
    :ok = Fake.fail(:transport)
    {:error, failure} = Fake.complete(Request.new("m", []), "k")
    failure
  end

  test "a draft wrapped whole in a code fence is the file inside it; a fence within the file stays" do
    assert Creation.unfenced("```\n# Soul\n\nI keep hymns.\n```") == "# Soul\n\nI keep hymns."
    assert Creation.unfenced("```markdown\nI am Ada.\n```\n") == "I am Ada."
    inside = "I keep recipes:\n\n```\nflour, water\n```\n\nand more."
    assert Creation.unfenced(inside) == inside
  end
end
