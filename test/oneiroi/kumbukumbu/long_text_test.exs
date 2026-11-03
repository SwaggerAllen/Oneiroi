defmodule Oneiroi.Kumbukumbu.LongTextTest do
  @moduledoc """
  Free text has no length the projection refuses. A provider's refusal of
  some 330 characters overflowed the capture failure's varchar(255), the
  projector stopped, the app restarted onto the same event, and
  production crash-looped (2026-11-03).
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

  test "a capture failure whose reason runs past 255 characters is projected whole" do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)

    reason =
      "nisaba_request_refused: 400 This endpoint's maximum context length is 1048576 tokens. " <>
        String.duplicate("However, you requested far more. ", 20)

    assert String.length(reason) > 255
    assert :ok = Kumbukumbu.fail_capture(resident.id, key, "turn-long", reason, brain)

    assert [%{reason: ^reason}] =
             Kumbukumbu.failures({:resident, resident.id})
  end
end
