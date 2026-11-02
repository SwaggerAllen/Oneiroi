defmodule Oneiroi.Xenia.Events do
  @moduledoc """
  The correspondence stream's events, version 1 (spec §6.6, F23):
  `xenia-<resident_id>`, one per resident. Third parties arrive as
  `CorrespondenceReceived`, pending the witness's reading unless their
  verified identity is trusted; the resident's replies are drafts the
  witness approves before anything is sent, and a send leaves a receipt.
  """

  defmodule CorrespondenceReceived do
    # `trusted` is the trust rule's answer at receipt: a verified sender
    # the witness trusts arrives approved, with no note (spec §6.6).
    use Oneiroi.Event,
      version: 1,
      fields: [
        :id,
        :number,
        :platform,
        :account,
        :external_id,
        :sender,
        :sender_name,
        :verified,
        :thread,
        :subject,
        :text,
        :sent_at,
        :trusted
      ],
      instants: [:sent_at]
  end

  defmodule CorrespondenceApproved do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number]
  end

  defmodule CorrespondenceRejected do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number]
  end

  defmodule CorrespondenceMarked do
    # The resident has read these (the seen mark).
    use Oneiroi.Event, version: 1, fields: [:id, :numbers]
  end

  defmodule CorrespondentTrusted do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :platform, :identity, :name]
  end

  defmodule CorrespondentDistrusted do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :platform, :identity]
  end

  defmodule ReplyDrafted do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :in_reply_to, :platform, :account, :thread, :to, :text]
  end

  defmodule ReplyApproved do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number]
  end

  defmodule ReplyDeclined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number]
  end

  defmodule ReplyMarkedSent do
    # The receipt: who sent it (the actor), and where it now is, if the
    # platform gives it an address.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :url]
  end
end
