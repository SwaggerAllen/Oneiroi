defmodule Oneiroi.Xenia.Commands do
  @moduledoc "The correspondence aggregate's commands; `id` is the resident's id."

  defmodule ReceiveMessage do
    # A third party's message as an inbound adapter read it (spec §6.6):
    # `platform` names the channel's kind (`email`, `substack`, any slug),
    # `account` the resident's own address on it, `external_id` the
    # platform's id for the message (the dedupe key with the two before),
    # `sender` the platform identity and `verified` whether the adapter
    # verified it (a DMARC pass for mail, a signed-in platform's account).
    use Oneiroi.Command,
      fields: [
        :id,
        :platform,
        :account,
        :external_id,
        :sender,
        :sender_name,
        :verified,
        :thread,
        :subject,
        :text,
        :sent_at
      ]
  end

  defmodule DecideMessage do
    # The witness's reading (F23): approve or reject, with a note.
    use Oneiroi.Command, decision: true, fields: [:id, :number, :approve]
  end

  defmodule TrustCorrespondent do
    use Oneiroi.Command, decision: true, fields: [:id, :platform, :identity, :name]
  end

  defmodule DistrustCorrespondent do
    use Oneiroi.Command, decision: true, fields: [:id, :platform, :identity]
  end

  defmodule MarkMessages do
    use Oneiroi.Command, fields: [:id, :numbers]
  end

  defmodule DraftReply do
    use Oneiroi.Command,
      fields: [:id, :in_reply_to, :platform, :account, :thread, :to, :text]
  end

  defmodule DecideReply do
    use Oneiroi.Command, decision: true, fields: [:id, :number, :approve]
  end

  defmodule MarkReplySent do
    use Oneiroi.Command, fields: [:id, :number, :url]
  end
end
