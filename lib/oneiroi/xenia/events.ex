defmodule Oneiroi.Xenia.Events do
  @moduledoc """
  The correspondence stream's events, version 1 (spec §6.6, F23 as
  amended 2026-11-02): `xenia-<resident_id>`, one per resident. Third
  parties arrive as `CorrespondenceReceived` and reach the resident at
  once, unless their identity is blocked, when only the fact of them is
  kept and never their words; the resident's replies are drafts the
  witness approves before anything is sent, and a send leaves a receipt.
  """

  defmodule CorrespondenceReceived do
    # `blocked` is the block rule's answer at receipt: a blocked sender's
    # message keeps its address and id (so a second delivery is still a
    # duplicate) and loses its name, subject and words, which are nil.
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
        :blocked
      ],
      instants: [:sent_at]
  end

  defmodule CorrespondenceMarked do
    # The resident has read these (the seen mark).
    use Oneiroi.Event, version: 1, fields: [:id, :numbers]
  end

  defmodule CorrespondentBlocked do
    # The actor is who blocked: the resident or the witness.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :platform, :identity, :name]
  end

  defmodule CorrespondentUnblocked do
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
