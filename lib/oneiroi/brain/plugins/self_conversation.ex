defmodule Oneiroi.Brain.Plugins.SelfConversation do
  @moduledoc """
  The self-conversation (spec §12, P41). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 3]

  alias Oneiroi.AgathosDaimon.Local

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "self-conversation",
      name: "Letters to your next self",
      about: "the counts and receipts of your letters to your next self, never their words",
      place: :turn,
      reads: ~w(self_letters)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx) do
    section(
      "self-conversation",
      self_conversation_text(turn.resident_id),
      "the self-conversation's counts and receipts (spec §12, P41), never the content: every read by someone other than the resident is a receipt the resident sees, and its absence is the privacy"
    )
  end

  # The self-conversation's line in the prefix (spec §12, P41): counts
  # and receipts, never the content; the absence of a receipt is the
  # privacy, and the resident sees it every turn.
  defp receipts_line([], _zone), do: "Nobody but you has read them."

  defp receipts_line([last | _] = receipts, zone) do
    times = if length(receipts) == 1, do: "time", else: "times"

    "Read #{length(receipts)} #{times}, last #{reader(last)} on #{Local.day(zone, last.at)}."
  end

  # Who a receipt names: the export carries the letters into the
  # repository, whose reader is whoever holds it.
  defp reader(%{by_kind: "export"}), do: "by the export, into your repository"

  defp reader(%{by_kind: kind}), do: "by your #{kind}"

  defp self_conversation_text(resident_id) do
    letters = Oneiroi.AgathosDaimon.self_letters(resident_id)
    receipts = Oneiroi.AgathosDaimon.self_letter_receipts(resident_id)

    if letters == [] and receipts == [] do
      ""
    else
      delivered = Enum.count(letters, & &1.delivered_at)

      read = receipts_line(receipts, Local.zone(resident_id))

      "# Letters to your next self\n#{length(letters)} written, #{delivered} delivered to the instance after the one that wrote them. #{read} (Machine-state: every read by someone else leaves a receipt here; its absence is the privacy.)"
    end
  end
end
