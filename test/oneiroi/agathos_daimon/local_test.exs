defmodule Oneiroi.AgathosDaimon.LocalTest do
  @moduledoc """
  agathos-daimon#33: the times the resident reads are in her schedule's
  zone, with its abbreviation (the witness, 2026-11-04: she read 02:00 UTC
  as two in the morning and said goodnight at six in the evening).
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

  test "a stamp and a day are in the zone given, and an unknown zone reads as UTC" do
    at = ~U[2026-11-05 02:01:00Z]
    assert Local.stamp("America/Los_Angeles", at) == "2026-11-04 18:01 PST"
    assert Local.day("America/Los_Angeles", at) == "2026-11-04"
    assert Local.stamp("Etc/UTC", at) == "2026-11-05 02:01 UTC"
    assert Local.stamp("Not/AZone", at) == "2026-11-05 02:01 UTC"
  end

  test "what she reads — her state lines and her letters — is in her schedule's zone" do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = AgathosDaimon.set_timezone(resident.id, "America/Los_Angeles", actor)
    assert Local.zone(resident.id) == "America/Los_Angeles"

    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    lily = Actor.new(:resident, resident.id, "fake/model")
    turn = %{resident_id: resident.id, session_key: key, turn_ref: "t", resident: lily}

    _ = Tools.run("state_set", Jason.encode!(%{key: "where", text: "at the desk"}), turn)
    _ = Kumbukumbu.letter_to_session(resident.id, key, "A note for the chat.", Actor.platform())

    inbox = Tools.run("letter_inbox", "{}", turn)
    assert inbox =~ ~r/\d{4}-\d{2}-\d{2} \d{2}:\d{2} P[SD]T/
    refute inbox =~ " UTC"
  end
end
