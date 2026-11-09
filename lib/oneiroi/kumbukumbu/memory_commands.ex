defmodule Oneiroi.Kumbukumbu.MemoryCommands do
  @moduledoc "The memory aggregate's commands; `id` is the resident's id."

  defmodule AddBookmark do
    use Oneiroi.Command,
      fields: [
        :id,
        :number,
        :session_key,
        :anchor_ref,
        :anchor_at,
        :turns_back,
        :line,
        :summary,
        :proposal_ref,
        :register
      ]
  end

  defmodule ExtendBookmark do
    use Oneiroi.Command, fields: [:id, :number, :turns_back]
  end

  defmodule PinBookmark do
    # `evidences`: the soul line the pin is leaf-evidence of, or nil.
    use Oneiroi.Command, fields: [:id, :number, :evidences]
  end

  defmodule RecordCitations do
    # The library's citations of bookmarks, as a snapshot (kumbukumbu#53):
    # `sources` maps each citing document's path to the bookmark numbers
    # it cites; a source left out cites none.
    use Oneiroi.Command, fields: [:id, :sources]
  end

  defmodule WeighBookmark do
    # The timeline's weight on a bookmark (kumbukumbu#51): `importance`
    # 0 to 3 (0 clears it), `status` a line of where the moment stands
    # now ("" clears it); either nil leaves it as it is.
    use Oneiroi.Command, fields: [:id, :number, :importance, :status]
  end

  defmodule UnpinBookmark do
    use Oneiroi.Command, fields: [:id, :number]
  end

  defmodule ProposeBookmark do
    use Oneiroi.Command, decision: true, fields: [:id, :ref, :session_key, :anchor_ref, :line]
  end

  defmodule DeclineBookmarkProposal do
    use Oneiroi.Command, decision: true, fields: [:id, :ref]
  end

  defmodule ProposeTag do
    use Oneiroi.Command, decision: true, fields: [:id, :slug], bounds: [slug: 64]
  end

  defmodule ApproveTag do
    use Oneiroi.Command, decision: true, fields: [:id, :slug]
  end

  defmodule RejectTag do
    use Oneiroi.Command, decision: true, fields: [:id, :slug]
  end

  defmodule CreateTag do
    use Oneiroi.Command,
      fields: [:id, :slug],
      bounds: [slug: 64]
  end

  defmodule RetireTag do
    use Oneiroi.Command, fields: [:id, :slug]
  end

  defmodule ApplyTag do
    use Oneiroi.Command, fields: [:id, :slug, :target_kind, :target_id]
  end

  defmodule RemoveTagging do
    use Oneiroi.Command, fields: [:id, :slug, :target_kind, :target_id]
  end

  defmodule Revise do
    use Oneiroi.Command,
      decision: true,
      fields: [:id, :target_kind, :target_id, :kind, :text]
  end

  defmodule AcceptRevision do
    use Oneiroi.Command, decision: true, fields: [:id, :number]
  end

  defmodule DeclineRevision do
    use Oneiroi.Command, decision: true, fields: [:id, :number]
  end

  # House letters (kumbukumbu#44): from one conversation of the resident
  # to another, or to the house; `from` and `from_session` are the
  # sender's conversation as the server names it, never the caller's word.
  defmodule SendHouseLetter do
    use Oneiroi.Command,
      fields: [:id, :from, :from_session, :to, :to_session, :in_reply_to, :text, :keepsake]
  end

  defmodule ReadHouseLetters do
    use Oneiroi.Command, fields: [:id, :numbers, :by]
  end
end
