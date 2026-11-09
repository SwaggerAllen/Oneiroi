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

  defmodule BlockCorrespondent do
    # Either party blocks an identity on a platform, with a note (xenia
    # #12); only the party who set a block lifts it.
    use Oneiroi.Command, decision: true, fields: [:id, :platform, :identity, :name]
  end

  defmodule UnblockCorrespondent do
    use Oneiroi.Command, decision: true, fields: [:id, :platform, :identity]
  end

  defmodule MarkMessages do
    use Oneiroi.Command, fields: [:id, :numbers]
  end

  defmodule DraftReply do
    # `supersedes` names a draft still waiting for the witness that this
    # one replaces (xenia#17).
    use Oneiroi.Command,
      fields: [:id, :in_reply_to, :platform, :account, :thread, :to, :text, :supersedes]
  end

  defmodule DecideReply do
    use Oneiroi.Command, decision: true, fields: [:id, :number, :approve]
  end

  defmodule MarkReplySent do
    use Oneiroi.Command, fields: [:id, :number, :url]
  end

  # The reader's allowlists (xenia#16): the sites its browser may reach
  # when it reads correspondence (`scrape`) and when it researches
  # (`research`); each an origin or `*`. The witness's to set.
  defmodule SetReaderSites do
    use Oneiroi.Command, fields: [:id, :scrape, :research]
  end

  # Routes (xenia#19), on `routes-<resident_id>`.
  defmodule DefineRoute do
    use Oneiroi.Command, fields: [:id, :key, :descriptor, :note]
  end

  defmodule AskRoute do
    use Oneiroi.Command, fields: [:id, :key, :note]
  end

  defmodule LandRoute do
    use Oneiroi.Command, fields: [:id, :number, :path]
  end

  defmodule FailRoute do
    use Oneiroi.Command, fields: [:id, :number, :reason]
  end

  # Profiles (xenia#19), on `profiles-<resident_id>`: the witness's.
  defmodule SetProfile do
    use Oneiroi.Command, fields: [:id, :key, :profile, :note]
  end

  defmodule RevokeProfile do
    use Oneiroi.Command, decision: true, fields: [:id, :key]
  end

  defmodule RestoreProfile do
    use Oneiroi.Command, decision: true, fields: [:id, :key]
  end
end
