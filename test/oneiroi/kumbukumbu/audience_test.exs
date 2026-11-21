defmodule Oneiroi.Kumbukumbu.AudienceTest do
  @moduledoc """
  The audience decision (kumbukumbu#79), pure, against Scarlett's seven
  worked examples (lily:design/audience-policy.md §8.3) and the rules
  around them: deny wins, a domain with no policy, the common room, the
  unresolved audience, the soft citation and the hard reason, the unwrap.
  """
  use ExUnit.Case, async: true

  alias Oneiroi.Kumbukumbu.Audience

  @andrew "account:00000000-0000-0000-0000-00000000000a"
  @lily "resident:00000000-0000-0000-0000-00000000000b"
  @recovery %{person: @andrew, domain: "recovery"}
  @winter %{person: @lily, domain: "lily-winter"}
  @work %{person: @andrew, domain: "oneiroi"}

  # His recovery is allow-list (no audience past the dyad unless named);
  # her winter likewise; the work domain open, but never to Jack.
  @policies [
    %{domain: @recovery, default: "deny", allow: [], deny: []},
    %{domain: @winter, default: "deny", allow: [], deny: []},
    %{domain: @work, default: "allow", allow: [], deny: [%{kind: "person", id: "jack"}]}
  ]
  @v1 %{version: 1, policies: @policies}

  defp input(id, labels), do: %{id: id, ref: "bookmark/#{id}", labels: labels}

  @dyad Audience.audience("dyad", "lily-andrew")
  @jack Audience.audience("person", "jack")
  @house Audience.audience("household", "h1")
  @public Audience.audience("publication", "substack")

  test "1. single-domain safe fragment: the work note reaches the house; recovery stays back, unnamed to the audience" do
    d =
      Audience.decide(
        [input("1", [@recovery]), input("2", [@work])],
        @house,
        @v1,
        :hard
      )

    assert d.allowed == ["2"]
    assert [%{id: "1", reason: :not_allowed}] = d.withheld
    told = Audience.told(d, hd(d.withheld))
    assert told == "withheld_by_policy (decision #{d.id})"
    refute told =~ "recovery"
  end

  test "2. mixed-domain care, the winter watch: the dyad holds both; Jack and the house hold neither" do
    watch = input("w", [@winter, @recovery])

    assert %{allowed: ["w"], withheld: []} = Audience.decide([watch], @dyad, @v1, :hard)
    assert %{allowed: [], withheld: [_]} = Audience.decide([watch], @jack, @v1, :hard)

    soft = Audience.decide([watch], @house, @v1, :soft)
    assert [%{conflicts: conflicts} = w] = soft.withheld
    assert conflicts == [@winter, @recovery]
    assert Audience.told(soft, w) =~ "in conflict with this audience: lily-winter, recovery"
  end

  test "3. uncited derivation: a derived input carries every input's labels, and the union travels" do
    sources = [input("a", [@recovery]), input("b", [@work])]
    d = Audience.decide(sources, @dyad, @v1, :soft)
    assert d.labels == [@recovery, @work]

    # The answer composed from them, cited nowhere, is labelled with the union.
    derived = input("answer", d.labels)

    assert %{allowed: [], withheld: [%{id: "answer"}]} =
             Audience.decide([derived], @house, @v1, :hard)
  end

  test "4. unclassified legacy: readable in the dyad, withheld past it" do
    old = input("old", :unclassified)
    assert %{allowed: ["old"], unclassified: true} = Audience.decide([old], @dyad, @v1, :hard)

    assert %{withheld: [%{reason: :unclassified}]} = Audience.decide([old], @house, @v1, :hard)
    # An empty label set is not the common room: it is unclassified.
    assert %{withheld: [%{reason: :unclassified}]} =
             Audience.decide([input("e", [])], @house, @v1, :hard)
  end

  test "5. revoked queued delivery: allowed when queued, withheld when re-decided at delivery" do
    granted = %{
      version: 2,
      policies: [
        %{domain: @recovery, default: "deny", allow: [%{kind: "household", id: "h1"}], deny: []}
      ]
    }

    revoked = %{
      version: 3,
      policies: [%{domain: @recovery, default: "deny", allow: [], deny: []}]
    }

    letter = input("q", [@recovery])

    queued = Audience.decide([letter], @house, granted, :hard)
    assert queued.allowed == ["q"]
    at_delivery = Audience.decide([letter], @house, revoked, :hard)
    assert at_delivery.allowed == []
    assert at_delivery.snapshot.version == 3
    refute at_delivery.id == queued.id
  end

  test "6. published history: the common room needs a policy to be published; a domain needs an allow" do
    note = input("n", :common_room)
    assert %{withheld: [_]} = Audience.decide([note], @public, @v1, :hard)
    # The common room reaches the house and Jack without a policy of its own.
    assert %{allowed: ["n"]} = Audience.decide([note], @house, @v1, :hard)
    assert %{allowed: ["n"]} = Audience.decide([note], @jack, @v1, :hard)

    open = %{
      version: 4,
      policies: [
        %{
          domain: %{person: "*", domain: "common-room"},
          default: "deny",
          allow: [%{kind: "publication", id: "*"}],
          deny: []
        }
      ]
    }

    assert %{allowed: ["n"]} = Audience.decide([note], @public, open, :hard)
  end

  test "7. indirect preload leak: a preloaded fragment for a thread is withheld, named only in her own context" do
    preload = input("USER.md#7", [@recovery])
    thread = Audience.audience("thread", "threads/x")

    soft = Audience.decide([preload], thread, @v1, :soft)
    assert Audience.told(soft, hd(soft.withheld)) =~ "recovery"

    hard = Audience.decide([preload], thread, @v1, :hard)
    refute Audience.told(hard, hd(hard.withheld)) =~ "recovery"
    refute Audience.told(hard, hd(hard.withheld)) =~ "USER.md"
  end

  test "deny wins over allow; a domain with no policy denies past the dyad; an unresolved audience denies" do
    both = %{
      version: 5,
      policies: [
        %{
          domain: @work,
          default: "allow",
          allow: [%{kind: "person", id: "jack"}],
          deny: [%{kind: "person", id: "*"}]
        }
      ]
    }

    assert %{withheld: [%{reason: :denied}]} =
             Audience.decide([input("w", [@work])], @jack, both, :hard)

    stray = %{person: @andrew, domain: "uncatalogued"}

    assert %{withheld: [%{reason: :no_policy}]} =
             Audience.decide([input("s", [stray])], @house, @v1, :hard)

    assert %{allowed: ["s"]} = Audience.decide([input("s", [stray])], @dyad, @v1, :hard)

    assert %{withheld: [%{reason: :unresolved_audience}]} =
             Audience.decide(
               [input("c", :common_room)],
               %{kind: "household", id: nil},
               @v1,
               :hard
             )
  end

  test "an unwrap is her deliberate act in her own composition: a new decision, recorded; none when hard" do
    soft = Audience.decide([input("1", [@recovery])], @house, @v1, :soft)
    assert {:error, %{site: :kumbukumbu_audience_unwrap_no_note}} = Audience.unwrap(soft, "1", "")
    assert {:ok, opened} = Audience.unwrap(soft, "1", "he asked me to share it")
    assert opened.allowed == ["1"]
    assert [%{id: "1", from: from}] = opened.unwrapped
    assert from == soft.id
    refute opened.id == soft.id

    hard = Audience.decide([input("1", [@recovery])], @house, @v1, :hard)

    assert {:error, %{site: :kumbukumbu_audience_unwrap_hard}} =
             Audience.unwrap(hard, "1", "anything")
  end
end
