defmodule Oneiroi.ProjectionFailureTest do
  @moduledoc """
  An event a projector cannot fold never stops the app (2026-11-03: one
  reason too long for its column restarted the projector onto the same
  event until the app went down). A data error is parked at once; a
  transient one is retried with backoff, then parked; the log names the
  event and never carries its data.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Commanded.Event.FailureContext
  alias Oneiroi.Kumbukumbu.Events.CaptureFailed
  alias Oneiroi.Projection

  @event %CaptureFailed{
    actor: nil,
    at: ~U[2026-11-03 14:30:21Z],
    reason: "the private words of a turn",
    turn_ref: "t1",
    session_key: "s1"
  }

  defp failure(context \\ %{}),
    do: %FailureContext{
      context: context,
      metadata: %{event_number: 5427, stream_id: "conversation-r1-s1"}
    }

  defp postgres(code),
    do: %Postgrex.Error{postgres: %{code: code, message: "the database's words"}}

  setup do
    test = self()

    :telemetry.attach(
      "parked-#{inspect(test)}",
      [:oneiroi, :projection, :parked],
      fn _name, measurements, meta, _ -> send(test, {:parked, measurements, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach("parked-#{inspect(test)}") end)
  end

  test "a value too long for its column is parked at once, named, and its words are not logged" do
    error = {:error, postgres(:string_data_right_truncation)}

    log =
      capture_log(fn ->
        assert :skip = Projection.failed("kumbukumbu_conversations", error, @event, failure())
      end)

    assert log =~ "kumbukumbu_conversations at event 5427"
    assert log =~ "Oneiroi.Kumbukumbu.Events.CaptureFailed"
    assert log =~ "string_data_right_truncation"
    refute log =~ "the private words of a turn"

    assert_received {:parked, %{count: 1},
                     %{projector: "kumbukumbu_conversations", event_number: 5427, attempts: 1}}
  end

  test "a transient refusal is retried with backoff, then parked once it has had its retries" do
    error = {:error, postgres(:deadlock_detected)}

    assert {:retry, 500, %FailureContext{context: %{attempts: 1}} = again} =
             Projection.failed("p", error, @event, failure())

    assert {:retry, 1000, again} = Projection.failed("p", error, @event, again)
    assert {:retry, 1500, again} = Projection.failed("p", error, @event, again)
    refute_received {:parked, _, _}

    capture_log(fn -> assert :skip = Projection.failed("p", error, @event, again) end)
    assert_received {:parked, _, %{attempts: 4}}
  end

  test "a raised exception and a bare term are parked, the stacktrace shape included" do
    capture_log(fn ->
      assert :skip =
               Projection.failed(
                 "p",
                 {:error, %ArgumentError{message: "x"}, []},
                 @event,
                 failure()
               )

      assert :skip = Projection.failed("p", {:error, :nope}, nil, failure())
    end)

    assert_received {:parked, _, %{event_type: "Oneiroi.Kumbukumbu.Events.CaptureFailed"}}
    assert_received {:parked, _, %{event_type: "unknown", reason: ":nope"}}
  end
end
