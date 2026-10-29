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
        :proposal_ref
      ]
  end

  defmodule ExtendBookmark do
    use Oneiroi.Command, fields: [:id, :number, :turns_back]
  end

  defmodule PinBookmark do
    use Oneiroi.Command, fields: [:id, :number]
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
    use Oneiroi.Command, decision: true, fields: [:id, :slug]
  end

  defmodule ApproveTag do
    use Oneiroi.Command, decision: true, fields: [:id, :slug]
  end

  defmodule RejectTag do
    use Oneiroi.Command, decision: true, fields: [:id, :slug]
  end

  defmodule CreateTag do
    use Oneiroi.Command, fields: [:id, :slug]
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

  defmodule DefineBehaviour do
    use Oneiroi.Command, fields: [:id, :number, :name, :trigger, :stance]
  end

  defmodule ChangeBehaviour do
    use Oneiroi.Command, fields: [:id, :number, :name, :trigger, :stance]
  end

  defmodule AffirmBehaviour do
    use Oneiroi.Command, decision: true, fields: [:id, :number]
  end

  defmodule EnactBehaviour do
    use Oneiroi.Command, fields: [:id, :number, :target_kind, :target_id]
  end
end
