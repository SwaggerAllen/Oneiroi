defmodule Oneiroi.HouseCitationsTest do
  @moduledoc """
  House citations (gaia#44, sima-qian#61, seshat#79; the witness and the
  resident, 2026-11-16): a house named once by a witness, its slug its own
  among houses; `house/<slug>:thread/<id>@<commit>` and `:doc/<path>`,
  marked so a house never shares a name with a resident; a read pinned to
  the commit it cites, saying what changed since; her documents' citations
  of the house resolved like her own, and a house that is not hers said
  so. The in-memory provider; no network.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.Citations
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
    {:ok, chat} = Kumbukumbu.main_session(id, witness.id, andrew)
    wren = %{id: id, slug: slug, actor: Actor.new(:resident, id), chat: chat}

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
    end)

    {:ok,
     witness: witness,
     andrew: andrew,
     wren: wren,
     house: "rook-#{System.unique_integer([:positive])}"}
  end

  defp run(name, args, r),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: r.id,
        session_key: r.chat,
        turn_ref: "t-#{r.slug}",
        resident: r.actor
      })

  test "a witness names the house once; the name is its own among houses", ctx do
    assert {:error, %{kind: :gaia_not_a_member}} =
             Seshat.household_name(ctx.wren.actor, ctx.house)

    assert {:error, %{kind: :gaia_household_name_invalid}} =
             Seshat.household_name(ctx.andrew, "Rook House")

    assert {:ok, %{slug: house}} = Seshat.household_name(ctx.andrew, ctx.house)
    assert house == ctx.house
    # The same name again changes nothing; another is refused: it never changes.
    assert {:ok, %{slug: ^house}} = Seshat.household_name(ctx.andrew, ctx.house)

    assert {:error, %{kind: :gaia_household_named}} =
             Seshat.household_name(ctx.andrew, "elsewhere")

    other = Fixtures.account!()
    them = Actor.new(:witness, other.id)
    {:ok, _} = Seshat.household_propose_contract(them, "Another house.", "founding")
    on_exit(fn -> File.rm_rf!(SimaQian.Household.dir(other.id)) end)
    assert {:error, %{kind: :gaia_household_name_taken}} = Seshat.household_name(them, ctx.house)
    assert Gaia.household_by_slug(ctx.house) == Gaia.household_id(ctx.witness.id)
  end

  test "a read says how to cite it; the citation opens what stood then and says what came since",
       ctx do
    {:ok, _} = Seshat.household_name(ctx.andrew, ctx.house)

    {:ok, posted} =
      Seshat.household_post(ctx.andrew, %{"title" => "Plans", "content" => "For the week."})

    read = run("household_read", %{path: posted.path}, ctx.wren)
    [_, cite] = Regex.run(~r/Cite as (house\/\S+?)\.(?:\s|$)/, read)
    assert cite =~ ~r|\Ahouse/#{ctx.house}:thread/[a-z0-9-]+@[0-9a-f]{12}\z|

    # A witness writes a thread once a beat: the next beat, he replies.
    Clock.Fake.advance(86_400)
    {:ok, _} = Seshat.household_reply(ctx.andrew, posted.path, %{"content" => "Yes, Sunday."})

    # The citation opens the thread as it stood: no reply yet, and one since.
    then = run("household_read", %{path: cite}, ctx.wren)
    refute then =~ "Yes, Sunday."
    assert then =~ "1 reply since it was cited"

    # Read as it stands, the reply is there and the citation moves on.
    now = run("household_read", %{path: posted.path}, ctx.wren)
    assert now =~ "Yes, Sunday."
    refute now =~ cite
  end

  test "her documents' citations of the house resolve like her own; not hers, unknown or never-committed, each said",
       ctx do
    {:ok, _} = Seshat.household_name(ctx.andrew, ctx.house)

    {:ok, posted} =
      Seshat.household_post(ctx.andrew, %{"title" => "Plans", "content" => "For the week."})

    {:ok, read} = Seshat.household_read(ctx.wren.actor, posted.path)

    text = """
    We agreed in #{read.cited_as}, and #{ctx.wren.slug}:bookmark/1 says why.
    Never #{ctx.house}:thread/x, which names a resident, not a house.
    Elsewhere: house/nowhere-at-all:doc/notes.md and house/#{ctx.house}:thread/#{String.replace_prefix(posted.path, "threads/", "")}@deadbeefdead.
    """

    cites = Citations.extract(text)

    assert Enum.map(cites, & &1.target) |> Enum.take(2) == [
             read.cited_as,
             "#{ctx.wren.slug}:bookmark/1"
           ]

    assert Enum.find(cites, &(&1.target == read.cited_as)).slug == "house/" <> ctx.house
    # Nothing is read out of the inside of a house citation as a resident's.
    refute Enum.any?(
             cites,
             &(&1.slug == ctx.house and String.contains?(read.cited_as, &1.target))
           )

    resident = %{id: ctx.wren.id, slug: ctx.wren.slug}
    [house_cite | _] = cites
    assert {:ok, label} = Citations.resolve(resident, house_cite)
    assert label =~ "Plans" and label =~ "house #{ctx.house}, thread, at "

    unknown = Enum.find(cites, &(&1.slug == "house/nowhere-at-all"))

    assert {:unresolved, "no house is named nowhere-at-all"} =
             Citations.resolve(resident, unknown)

    never = Enum.find(cites, &String.ends_with?(&1.ref, "@deadbeefdead"))

    assert Citations.resolve(resident, never) ==
             {:unresolved, "house #{ctx.house} never had that commit"}

    # A house that is not hers: named, and not where she lives.
    other = Fixtures.account!()
    them = Actor.new(:witness, other.id)
    {:ok, _} = Seshat.household_propose_contract(them, "Another house.", "founding")
    on_exit(fn -> File.rm_rf!(SimaQian.Household.dir(other.id)) end)
    {:ok, _} = Seshat.household_name(them, ctx.house <> "-b")

    {:ok, theirs} = Citations.house("house/#{ctx.house}-b:doc/CONTRACT.md")

    assert {:unresolved, why} =
             Citations.resolve(resident, %{
               slug: "house/" <> theirs.house,
               kind: "doc",
               ref: "CONTRACT.md"
             })

    assert why =~ "is not yours"
  end

  test "an unnamed house reads as before and says it cannot be cited yet", ctx do
    {:ok, posted} =
      Seshat.household_post(ctx.andrew, %{"title" => "Plans", "content" => "For the week."})

    read = run("household_read", %{path: posted.path}, ctx.wren)
    assert read =~ "For the week."
    assert read =~ "A witness names the house before its threads can be cited."
  end

  test "the parts of a house citation, and what is not one" do
    assert {:ok,
            %{house: "rook", kind: "thread", path: "threads/2026-11-16-plans", at: "a1b2c3d4e5f6"}} =
             Citations.house("house/rook:thread/2026-11-16-plans@a1b2c3d4e5f6")

    assert {:ok, %{kind: "doc", path: "design/plan.md", at: nil}} =
             Citations.house("house/rook:doc/design/plan.md")

    for not_one <- [
          "rook:thread/x",
          "house/Rook:thread/x",
          "house/rook:bookmark/1",
          "threads/x",
          "house/rook:thread/x@zz"
        ],
        do: assert(Citations.house(not_one) == :error, not_one)
  end
end
