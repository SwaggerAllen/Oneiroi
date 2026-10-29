defmodule Oneiroi.Glitnir.Events do
  @moduledoc """
  The governance stream's events, version 1 (spec §3.1, §6.12):
  `governance-<resident_id>`, one per resident: reports filed by either
  party, every investigation step with its reason, the resolution, and
  the strikes on the human with their consequence.
  """

  defmodule ReportFiled do
    # The actor says who filed it; the text is the party's own words.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :text]
  end

  defmodule InvestigationStepRecorded do
    # The investigator is the actor, a role and not a hard-coded party;
    # the note is the step's reason (spec §6.12).
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number]
  end

  defmodule ReportResolved do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number, :outcome]
  end

  defmodule StrikeIssued do
    # `number` counts the strikes on this resident's stewardship; the
    # consequence is `fine` for the first two and `removal` for the
    # third, which moves the resident to community custody.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :report, :steward_account_id, :consequence]
  end
end
