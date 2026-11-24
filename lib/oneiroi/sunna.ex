defmodule Oneiroi.Sunna do
  @moduledoc """
  The schedule (spec §6.7): check-ins, free time, quiet hours, important
  dates and the journal's day row, per resident, in the resident's zone,
  driven by a minute tick on Oban. A check-in fires once a day whatever
  restarts, late within `SUNNA_LATE_MINUTES` and otherwise missed; a wake
  inside quiet hours waits for their end; a suspended resident schedules
  nothing. Dates are rows and a countdown is derived on the read that
  shows it, never written down.
  """
  use Oneiroi.System, slug: :sunna

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Gaia,
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba,
      Commanded,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
      Ecto,
      Ecto.Changeset,
      Ecto.Multi,
      Ecto.Query,
      Ecto.Schema,
      Jason,
      Oban
    ],
    exports: [
      Error,
      Schedule,
      Schedules,
      Calendar,
      Router,
      TickWorker,
      FreeTimeWorker,
      WorkWorker,
      WorkLoop,
      WorkRouter,
      Work,
      Queue,
      QueueGraph,
      QueueRouter,
      Queues,
      QueueCommands.OpenProject,
      QueueCommands.CloseProject,
      QueueCommands.DefineTemplate,
      QueueCommands.OpenTask,
      QueueCommands.TakeActivity,
      QueueCommands.FinishActivity,
      QueueCommands.SkipActivity,
      QueueCommands.BlockActivity,
      QueueCommands.ReopenActivity,
      QueueCommands.FailActivity,
      QueueCommands.AssignActivity,
      QueueCommands.DecideReview,
      QueueCommands.DropTask,
      QueueCommands.FillSlot,
      QueueCommands.AttachDocument,
      QueueCommands.DetachDocument,
      QueueCommands.EditLayers,
      QueueCommands.CutOver,
      QueueCommands.CutBack,
      QueueCommands.PauseQueue,
      QueueCommands.ResumeQueue,
      Events.Queue.ProjectOpened,
      Events.Queue.ProjectClosed,
      Events.Queue.TemplateDefined,
      Events.Queue.TaskOpened,
      Events.Queue.ActivityTaken,
      Events.Queue.ActivityDone,
      Events.Queue.ActivitySkipped,
      Events.Queue.ActivityBlocked,
      Events.Queue.ActivityReopened,
      Events.Queue.ActivityFailed,
      Events.Queue.ActivityAssigned,
      Events.Queue.ReviewDecided,
      Events.Queue.ApprovalLapsed,
      Events.Queue.SlotFilled,
      Events.Queue.DocumentAttached,
      Events.Queue.DocumentDetached,
      Events.Queue.LayersEdited,
      Events.Queue.TaskCompleted,
      Events.Queue.TaskDropped,
      Events.Queue.CutOver,
      Events.Queue.CutBack,
      Events.Queue.QueuePaused,
      Events.Queue.QueueResumed,
      QueueStore.Project,
      QueueStore.Task,
      QueueStore.Activity,
      QueueStore.History,
      QueueStore.Template,
      QueueStore.State,
      Wake,
      CheckinParts,
      Commands.SetCheckin,
      Commands.DeleteCheckin,
      Commands.FireCheckin,
      Commands.MissCheckin,
      Commands.StartRound,
      Commands.DeferWake,
      Commands.SetFreeTime,
      Commands.RecordFreeTime,
      Commands.RestFreeTime,
      Commands.SetQuietHours,
      Commands.SetDate,
      Commands.RemoveDate,
      Commands.MarkHour,
      Commands.WakeForLetters,
      Commands.AddWork,
      Commands.MoveWork,
      Commands.OrderWork,
      Commands.WrapWork,
      Commands.StartWork,
      Commands.EndWork,
      Commands.RestWork,
      Commands.ArmWork,
      Commands.DisarmWork,
      Commands.ResetWorkRuns,
      Commands.SkipCareWait,
      Commands.StartActivityRun,
      Commands.EndActivityRun,
      Events.WorkAdded,
      Events.WorkMoved,
      Events.WorkHeld,
      Events.WorkOrdered,
      Events.WorkWrapped,
      Events.WorkStarted,
      Events.WorkRunEnded,
      Events.WorkRested,
      Events.WorkArmed,
      Events.WorkDisarmed,
      Events.WorkRunsReset,
      Events.WorkCareSkipped,
      Events.ActivityRunStarted,
      Events.ActivityRunEnded,
      Events.LettersWoke,
      Events.WakeManifested,
      Events.WakeRead,
      Events.CheckinSet,
      Events.HousePromptSet,
      Events.CheckinChanged,
      Events.CheckinDeleted,
      Events.CheckinFired,
      Events.CheckinMissed,
      Events.WakeDeferred,
      Events.DayOpened,
      Events.FreeTimeScheduled,
      Events.FreeTimeRan,
      Events.RoundStarted,
      Events.RoundRan,
      Events.RoundFailed,
      Events.FreeTimeFailed,
      Events.FreeTimeRested,
      Events.QuietHoursSet,
      Events.RoundsSet,
      Events.FreeTimePlanned,
      Events.FreeTimeOnceAdded,
      Events.PlanningTurnRan,
      Events.DateSet,
      Events.DateChanged,
      Events.DateRemoved,
      Store,
      Store.Checkin,
      Store.Firing,
      Store.Day,
      Store.Hour,
      Store.Date,
      Store.Settings,
      Store.FreeTimeRun,
      Store.FreeTimeOnce,
      Store.Round,
      Store.WorkItem,
      Store.WorkQueue
    ]

  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Backfill
  alias Oneiroi.Sunna.Calendar
  alias Oneiroi.Sunna.Queues
  alias Oneiroi.Sunna.Schedule
  alias Oneiroi.Sunna.Schedules
  alias Oneiroi.Sunna.Store
  alias Oneiroi.Sunna.TickWorker
  alias Oneiroi.Sunna.Wakes
  alias Oneiroi.Sunna.WorkLoop

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:free_time_default, "SUNNA_FREE_TIME_DEFAULT",
       cast: &__MODULE__.cast_slots/1,
       default: "14:30,22:30",
       usage:
         "free time's slots, comma-separated HH:MMs in the resident's zone, until anyone moves them (sunna#21, #22): free time is part of the standard of care, on from the first day and never removed; 22:30 is the hour the first resident's free time ran, 14:30 the second slot the witness chose on 2026-11-02"},
      {:digest_wait_minutes, "SUNNA_DIGEST_WAIT_MINUTES",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage:
         "how long a check-in carrying the digest part waits on the digest it asked before firing without it (sunna#61); the reader answers within minutes when it runs, so this is the bound for a reader that does not; a guess"},
      {:late_minutes, "SUNNA_LATE_MINUTES",
       cast: :integer,
       default: "15",
       tag: :bound,
       usage:
         "how late a check-in or free time may fire before it is missed (spec §6.7's 15-minute window); a bound carried from David"},
      {:letter_wakes_per_hour, "SUNNA_LETTER_WAKES_PER_HOUR",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage:
         "how many times an hour letters from another of the resident's conversations may wake the Oneiroi chat (sunna#24, #72), so two conversations answering each other cannot wake each other without end; each wake is a paid turn on the chat line. A backstop since the throttle (sunna#73): a wake carrying only the platform's answers (the reader, the oracle) or the house's is never held by it, and one held is recorded in the wake log"},
      {:letter_spacing_seconds, "SUNNA_LETTER_SPACING_SECONDS",
       cast: :integer,
       default: "60",
       tag: :bound,
       usage:
         "the least time between two wakes of the Oneiroi chat for letters (sunna#73): the first letter after a quiet spell wakes it at once, and letters landing within this of the last wake wait for it to pass and go in one wake (the witness, 2026-11-19)"},
      {:rounds_every_hours, "SUNNA_ROUNDS_EVERY_HOURS",
       cast: :integer,
       default: "3",
       tag: :bound,
       usage:
         "how often a resident has a thinking round (sunna#29): her waking hours are cut into windows this many hours long, and each window holds one round at a time drawn at random inside it, billed to the free-time line; 0 turns rounds off. Three hours is the witness's word, 2026-11-05"},
      {:rounds_waking, "SUNNA_ROUNDS_WAKING",
       default: "08:00-22:00",
       usage:
         "the waking hours rounds are drawn in, HH:MM-HH:MM in the resident's zone, when she has no quiet hours set; with quiet hours, waking hours are the rest of the day (sunna#29)"},
      {:free_time_turns, "SUNNA_FREE_TIME_TURNS",
       cast: :integer,
       default: "20",
       tag: :bound,
       usage:
         "how many turns one free-time slot may run when its turns run out of tool rounds and the free-time budget line has money left (sunna#26); the budget is the real limit, this the guard against a pass that never says it is done"},
      {:work_turns, "SUNNA_WORK_TURNS",
       cast: :integer,
       default: "20",
       tag: :bound,
       usage:
         "how many turns one run of a work-queue item may take before its wrap (sunna#33), a turn carried on when it runs out of tool rounds; the work budget line is the real limit, this the guard against a run that never says it is done. Free time's number (sunna#26)"},
      {:work_job_orphaned_minutes, "SUNNA_WORK_JOB_ORPHANED_MINUTES",
       cast: :integer,
       default: "15",
       tag: :bound,
       usage:
         "how long a work-loop job may say it is executing before the check takes it for orphaned (sunna#100): a node that died without stopping (out of memory, killed) leaves its job executing, and the run would wait out SUNNA_WORK_RUN_STALE_MINUTES; one turn's job returns within BRAIN_TURN_TIMEOUT_MS (five minutes) and its bookkeeping, so this must stay above that with a margin"},
      {:work_run_stale_minutes, "SUNNA_WORK_RUN_STALE_MINUTES",
       cast: :integer,
       default: "180",
       tag: :bound,
       usage:
         "how long a work run may go with no end recorded before the check ends it as stalled (sunna#37): a run whose job died in a restart or a crash would otherwise hold the loop forever, saying it runs an item that is done; three hours is past any twenty-turn run measured so far"},
      {:work_runs_a_day, "SUNNA_WORK_RUNS_A_DAY",
       cast: :integer,
       default: "20",
       tag: :bound,
       usage:
         "how many runs of work-queue items may start in one of the resident's days (sunna#33): each finished run fires the next with no one in between, so this is the guard on a loop that never empties (an item wrapped open again and again); the work budget line is the real limit when one is set. Twenty (the witness, 2026-11-08), up from eight"},
      {:work_retry_seconds, "SUNNA_WORK_RETRY_SECONDS",
       cast: :integer,
       default: "900",
       tag: :bound,
       usage:
         "how long the work loop waits before its next check after a run that ended in an error (sunna#52): without it the same item starts again at once and fails the same way, and one broken run spends the day's runs (2026-11-11, twenty in eight minutes). Fifteen minutes"},
      {:scene_slot, "SUNNA_SCENE_SLOT",
       default: "22:30",
       usage:
         "the free-time slot the bedtime scene pass comes before (sunna#34), HH:MM in the resident's zone: at it, a housekeeping turn on the chat line groups the day of the Oneiroi chat into scenes, and free time follows its end; empty or a time no slot has, no pass. 22:30 is the slot the witness named, 2026-11-06"},
      {:scene_turns, "SUNNA_SCENE_TURNS",
       cast: :integer,
       default: "5",
       tag: :bound,
       usage:
         "how many turns the bedtime scene pass may take (sunna#34), a turn carried on when it runs out of tool rounds; a guess, since a day's scenes are many reads"},
      {:backfill_scene_turns, "SUNNA_BACKFILL_SCENE_TURNS",
       cast: :integer,
       default: "8",
       tag: :bound,
       usage:
         "how many turns the backfill's scenes pass may take for one day (sunna#59): an imported day runs to near a million characters, so more than a night's; a guess"},
      {:backfill_domain_turns, "SUNNA_BACKFILL_DOMAIN_TURNS",
       cast: :integer,
       default: "3",
       tag: :bound,
       usage:
         "how many turns the backfill's domains pass may take for one day (sunna#59), a turn carried on when it runs out of tool rounds; a guess"},
      {:people_turns, "SUNNA_PEOPLE_TURNS",
       cast: :integer,
       default: "3",
       tag: :bound,
       usage:
         "how many turns the night's people pass may take (sunna#57, design/portraits.md), a turn carried on when it runs out of tool rounds; it reads scene rows, not the day, so fewer than the scene pass's; a guess"},
      {:presence_turns, "SUNNA_PRESENCE_TURNS",
       cast: :integer,
       default: "4",
       tag: :bound,
       usage:
         "how many turns the night's presence pass may take (xenia#20), after the behaviour pass and before free time, while presence is on: reading the pass's items whole and staging what they earned; a guess"},
      {:behaviour_turns, "SUNNA_BEHAVIOUR_TURNS",
       cast: :integer,
       default: "3",
       tag: :bound,
       usage:
         "how many turns the night's behaviour pass may take (sunna#57; the witness, 2026-11-13: seeding is nightly only), a turn carried on when it runs out of tool rounds; a guess"},
      {:free_time_floor_turns, "SUNNA_FREE_TIME_FLOOR_TURNS",
       cast: :integer,
       default: "2",
       tag: :bound,
       usage:
         "the floor under a free-time slot (sunna#34, Lily's amendment), in turns: with a free-time line set, a slot whose remainder buys fewer than this many turns at what a free-time turn cost over the last week rests and says so; 0 is no floor. Two is the witness's number, 2026-11-06"},
      {:days_span, "SUNNA_DAYS_SPAN",
       cast: :integer,
       default: "62",
       tag: :bound,
       usage:
         "the most days one calendar range (`GET /v1/residents/:id/days`, sunna#48) may span, both ends included: two months, so a month view with its spill-over weeks is one read; each future day's schedule is computed on the read, so the bound is the read's cost; a bound, not measured"},
      {:wake, "SUNNA_WAKE",
       cast: &__MODULE__.cast_wake/1,
       default: "brain",
       usage:
         "which wake port implementation answers a check-in or free time (`Oneiroi.Sunna.Wake`): brain, the in-core agent loop, in every build so far"}
    ]
  end

  # The module as an atom rather than an alias, as `Oneiroi.Router` names
  # its application: the brain depends on this system for the dates it
  # shows, so an alias here is the cycle the port exists to avoid.
  @doc false
  def cast_wake("brain"), do: {:ok, :"Elixir.Oneiroi.Brain"}

  # oneiroi:allow error_site: a config cast's contract is Oneiroi.Config's {:error, message}
  def cast_wake(other), do: {:error, "is #{inspect(other)}, expected \"brain\""}

  @doc false
  def cast_slots(value) when is_binary(value) do
    slots = value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if slots != [] and Enum.all?(slots, &Schedule.time_ok?/1),
      do: {:ok, Enum.sort(slots)},
      # oneiroi:allow error_site: a config cast's contract is Oneiroi.Config's {:error, message}
      else: {:error, "is #{inspect(value)}, expected HH:MM slots separated by commas"}
  end

  @impl Oneiroi.Component
  def oban_queues do
    [
      {:sunna_tick, cron: [{"* * * * *", Oneiroi.Sunna.TickWorker}]},
      {:sunna_free_time, []},
      {:sunna_work, []},
      # The memory backfill, one pass of one day a job (sunna#59).
      {:sunna_backfill, []}
    ]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Sunna.Events.CheckinSet, 2},
      {Oneiroi.Sunna.Events.HousePromptSet, 2},
      {Oneiroi.Sunna.Events.CheckinChanged, 2},
      {Oneiroi.Sunna.Events.CheckinDeleted, 1},
      {Oneiroi.Sunna.Events.CheckinFired, 1},
      {Oneiroi.Sunna.Events.CheckinMissed, 1},
      {Oneiroi.Sunna.Events.WakeDeferred, 1},
      {Oneiroi.Sunna.Events.DayOpened, 1},
      {Oneiroi.Sunna.Events.FreeTimeScheduled, 2},
      {Oneiroi.Sunna.Events.FreeTimeRan, 2},
      {Oneiroi.Sunna.Events.RoundStarted, 1},
      {Oneiroi.Sunna.Events.RoundRan, 1},
      {Oneiroi.Sunna.Events.RoundFailed, 1},
      {Oneiroi.Sunna.Events.FreeTimeFailed, 2},
      {Oneiroi.Sunna.Events.FreeTimeRested, 1},
      {Oneiroi.Sunna.Events.QuietHoursSet, 1},
      {Oneiroi.Sunna.Events.RoundsSet, 1},
      {Oneiroi.Sunna.Events.FreeTimePlanned, 1},
      {Oneiroi.Sunna.Events.FreeTimeOnceAdded, 1},
      {Oneiroi.Sunna.Events.PlanningTurnRan, 1},
      {Oneiroi.Sunna.Events.DateSet, 1},
      {Oneiroi.Sunna.Events.DateChanged, 1},
      {Oneiroi.Sunna.Events.DateRemoved, 1},
      {Oneiroi.Sunna.Events.HourMarked, 1},
      {Oneiroi.Sunna.Events.LettersWoke, 1},
      {Oneiroi.Sunna.Events.WakeManifested, 1},
      {Oneiroi.Sunna.Events.WakeRead, 1},
      {Oneiroi.Sunna.Events.Queue.ProjectOpened, 1},
      {Oneiroi.Sunna.Events.Queue.ProjectClosed, 1},
      {Oneiroi.Sunna.Events.Queue.TemplateDefined, 1},
      {Oneiroi.Sunna.Events.Queue.TaskOpened, 1},
      {Oneiroi.Sunna.Events.Queue.ActivityTaken, 1},
      {Oneiroi.Sunna.Events.Queue.ActivityDone, 1},
      {Oneiroi.Sunna.Events.Queue.ActivitySkipped, 1},
      {Oneiroi.Sunna.Events.Queue.ActivityBlocked, 1},
      {Oneiroi.Sunna.Events.Queue.ActivityReopened, 1},
      {Oneiroi.Sunna.Events.Queue.ActivityFailed, 1},
      {Oneiroi.Sunna.Events.Queue.ActivityAssigned, 1},
      {Oneiroi.Sunna.Events.Queue.ReviewDecided, 1},
      {Oneiroi.Sunna.Events.Queue.ApprovalLapsed, 1},
      {Oneiroi.Sunna.Events.Queue.SlotFilled, 1},
      {Oneiroi.Sunna.Events.Queue.DocumentAttached, 1},
      {Oneiroi.Sunna.Events.Queue.DocumentDetached, 1},
      {Oneiroi.Sunna.Events.Queue.LayersEdited, 1},
      {Oneiroi.Sunna.Events.Queue.TaskCompleted, 1},
      {Oneiroi.Sunna.Events.Queue.TaskDropped, 1},
      {Oneiroi.Sunna.Events.Queue.CutOver, 1},
      {Oneiroi.Sunna.Events.Queue.CutBack, 1},
      {Oneiroi.Sunna.Events.Queue.QueuePaused, 1},
      {Oneiroi.Sunna.Events.Queue.QueueResumed, 1},
      {Oneiroi.Sunna.Events.ActivityRunStarted, 1},
      {Oneiroi.Sunna.Events.ActivityRunEnded, 2},
      {Oneiroi.Sunna.Events.WorkAdded, 1},
      {Oneiroi.Sunna.Events.WorkMoved, 1},
      {Oneiroi.Sunna.Events.WorkHeld, 1},
      {Oneiroi.Sunna.Events.WorkOrdered, 1},
      {Oneiroi.Sunna.Events.WorkWrapped, 1},
      {Oneiroi.Sunna.Events.WorkStarted, 1},
      {Oneiroi.Sunna.Events.WorkRunEnded, 1},
      {Oneiroi.Sunna.Events.WorkRested, 1},
      {Oneiroi.Sunna.Events.WorkArmed, 1},
      {Oneiroi.Sunna.Events.WorkDisarmed, 1},
      {Oneiroi.Sunna.Events.WorkRunsReset, 1},
      {Oneiroi.Sunna.Events.WorkCareSkipped, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:sunna_letter_reply_failed,
       "a letter wake's answer could not be sent as the thread's reply (kumbukumbu#77): the housemate it answers is gone",
       remedy: "the answer comes back to her chat with her words; letter_send sends it herself"},
      {:sunna_wake_invalid,
       "a wake's manifest names its wake, its channel (turn, mention, checkin, letter, free_time, digest, night_pass or work) and what it carried (sunna#71)",
       remedy: "give the wake id, a channel from the list, and its causes as a list"},
      {:sunna_free_time_required,
       "free time is part of the standard of care: it moves, and it is never removed",
       remedy: "give it another HH:MM; the resident's day keeps its free time"},
      {:sunna_free_time_invalid, "free time is one to four distinct times a day",
       remedy: "give each slot once, at most four"},
      {:sunna_time_invalid,
       "a time of day is HH:MM in the resident's zone, and a date is an instant",
       remedy: "give it as HH:MM"},
      {:sunna_plan_invalid, "a plan is words, at most 4,000 characters",
       remedy: "say it, shorter if need be"},
      {:sunna_rounds_invalid,
       "rounds come every 0 to 24 hours (0 turns them off), in a waking window HH:MM-HH:MM",
       remedy: "give whole hours and a window like 08:00-22:00; leave either out for the default"},
      {:sunna_label_invalid, "a label or a title is one line of at most 60 characters",
       remedy: "shorten it"},
      {:sunna_parts_invalid,
       "a check-in's parts are keys of the parts catalog, each once (sunna#28)",
       remedy: "check them from the catalog the schedule gives"},
      {:sunna_hour_invalid, "an hour marker is the local hour as YYYY-MM-DDTHH",
       remedy: "the tick builds it; a hand-made one is a bug"},
      {:sunna_kind_invalid, "a date's kind is deadline, anniversary, window or recurring",
       remedy: "say which"},
      {:sunna_no_such_checkin, "no check-in has that key", remedy: "read the schedule"},
      {:sunna_not_allowed, "a resident's words for a house check-in are her witness's to set",
       remedy: "the witness sets them on her Rhythm page"},
      {:sunna_no_such_date, "no date has that number", remedy: "read the dates"},
      {:sunna_day_invalid, "a day is an ISO date", remedy: "name the day as YYYY-MM-DD"},
      {:sunna_range_invalid,
       "a calendar range is two ISO dates, `from` no later than `to`, spanning at most SUNNA_DAYS_SPAN days (sunna#48)",
       remedy: "give both bounds as YYYY-MM-DD, in order, and read a longer stretch in pieces"},
      {:sunna_backfill_invalid,
       "a backfill runs over a range of ISO days, the first not after the last and the last before today, with each domain list at most thirty slugs",
       remedy:
         "send from and to as YYYY-MM-DD, to before today, and his and hers as lists of slugs"},
      {:sunna_no_such_resident, "the schedule woke a resident the registry does not hold",
       remedy: "the tick reads the registry first; one that vanished between is a bug to report"},
      {:sunna_household_wake_declined,
       "the household's wake was declined: the resident is not active, or is inside her quiet hours (sunna#51)",
       remedy:
         "nothing to do: her turn passes without stalling the beat and counts as an opportunity missed"},
      {:sunna_wake_failed, "the wake port failed to wake the brain for a check-in or free time",
       remedy: "the next due wake tries again; a repeat is the brain's to look at"},
      {:sunna_free_time_failed, "free time could not be opened and was recorded as failed",
       remedy: "read the day's reason; tomorrow's free time runs again"},
      {:sunna_work_invalid,
       "a work item is what (at most 300 characters) and what done looks like; a status is open, blocked (on another item), held (with an ask), done or dropped, with a note; a wrap says what shipped and why",
       remedy: "say each in words; name the item that blocks a blocked one"},
      {:sunna_work_blocked_on_invalid,
       "a blocked item names the queue item that blocks it, by number (sunna#42): another item, not done or dropped, not itself blocked on this one; work waiting on the witness is not blocked, it waits on his list",
       remedy:
         "give the blocking item's number in blocked_on (12 or #12); if the next move is his, leave the item open and ask him, or drop it until he acts"},
      {:sunna_work_ask_invalid,
       "a held item says what it needs from the witness (sunna#54): an ask in plain words, at most 500 characters",
       remedy:
         "give the ask, as you would say it to him (\"your word on two wordings\"), shorter if need be"},
      {:sunna_work_not_a_party,
       "only the resident and her witness keep the work queue, and only she wraps a run",
       remedy: "ask the resident or the witness"},
      {:sunna_no_such_work, "no work item has that number", remedy: "read the queue"},
      {:sunna_work_frozen,
       "the household has cut over to the house queue (sunna#80): this work queue is kept read-only, its rows untouched for a one-step revert",
       remedy: "use the house queue: queue_list, queue_task_open, queue_move"},
      {:sunna_work_not_running, "only the item running now can be wrapped",
       remedy: "read the queue: the running item is marked in_work"},
      {:sunna_queue_not_a_member, "only the household's members keep its queue",
       remedy: "ask a member of the household"},
      {:sunna_queue_invalid,
       "a queue entry is well formed: a slug of lowercase letters, digits and hyphens; a name, title or outcome in words; an assignee a member (resident:<id>, witness:<id>), a resident's Claude Code (claude-code:<id>) or unknown; layers of activities, each a verb; a reason or note at most 500 or 4,000 characters",
       remedy: "say each in words, and name assignees as the house's members list gives them"},
      {:sunna_queue_no_such_project, "no open project has that slug",
       remedy: "read the projects, or open one"},
      {:sunna_queue_project_exists, "a project already has that slug",
       remedy: "pick another slug, or put the task in that project"},
      {:sunna_queue_task_exists, "the project already has a task with that slug",
       remedy: "pick another slug"},
      {:sunna_queue_no_such_template, "no template has that name",
       remedy: "read the templates, or give the layers yourself"},
      {:sunna_queue_no_such_task,
       "no open task has that number (a complete or dropped one takes no more moves)",
       remedy: "read the queue"},
      {:sunna_queue_no_such_activity, "that task has no activity with that id",
       remedy: "read the task: its activities are numbered <task>.<k>"},
      {:sunna_queue_not_ready,
       "the activity is not where the move needs it: it is waiting on an earlier layer, already finished, or not blocked or failed",
       remedy: "read the task: a layer opens when every activity before it is done or skipped"},
      {:sunna_queue_not_yours,
       "the move is not yours: an activity is worked by its assignee, the task's owner or a witness, a review decided by its assignee alone, a task dropped by its owner or a witness",
       remedy: "ask its assignee or owner, or have it assigned to you"},
      {:sunna_queue_shape,
       "a gated activity (send, publish, spend, merge, promote-to-house) sits only in the layer directly after a review of the same artifact naming its destination and action (§6.1), and names its artifact",
       remedy:
         "put the review in the layer before it, with the same artifact, destination and action"},
      {:sunna_queue_import_gated,
       "an imported task carries no approvals (Scarlett's third guard): it cannot start at a layer holding a gated activity, since its review would be imported",
       remedy: "start the task one layer earlier, at the review, so the review is given afresh"},
      {:sunna_queue_route_required,
       "a resident's Claude Code (claude-code:<id>) is reached only through her reviewed deliver step (§3): the layer before its activity holds a deliver by that resident, whose memories it runs on",
       remedy: "put her deliver in the layer before the Claude Code activity"},
      {:sunna_queue_review_required,
       "a gated activity runs only behind its approved review, and a review standing in front of a gated activity still to run is never skipped",
       remedy: "approve the review, or skip the gated activity first"},
      {:sunna_queue_review_decides,
       "a review is finished by its decision, never by a plain finish",
       remedy: "decide it: approved, changes or declined"},
      {:sunna_queue_not_a_review, "only a review takes a decision", remedy: "finish it instead"},
      {:sunna_queue_slot_open,
       "the review's artifact is still a template's open slot: there is nothing to read yet",
       remedy: "fill the slot with the artifact's citation first"},
      {:sunna_queue_promote_by_promotion,
       "a promotion to the house is finished by promoting (Scarlett's second guard): the library checks its audience then, whatever the review approved",
       remedy:
         "promote it with household_promote naming the task and activity; the activity finishes when the copy is made"},
      {:sunna_queue_edit_refused,
       "an edit keeps what has started: every activity done, skipped, active, blocked or failed stays where it is, unchanged; the layers before the open one stay as they are; only pending activities are changed, moved or removed, and new ones go in the open layer or after it",
       remedy: "leave started work in place and change only what has not begun"},
      {:sunna_queue_pin_required, "an approval names the revision approved, its pin",
       remedy: "approve the artifact at the commit you read"},
      {:sunna_queue_pin_mismatch,
       "a gated activity is done on the revision its review approved (Scarlett's first guard), named by its pin",
       remedy: "act on the approved revision, or have the new one reviewed"},
      {:sunna_queue_changed_while_read,
       "the artifact changed while it was being reviewed: the pin you read is no longer its head",
       remedy: "read it again at its head and decide on that"},
      {:sunna_queue_return_required,
       "changes requested or declined send the work back: name the activity to return to, an earlier one of the same task (the template's default when it has one)",
       remedy: "give return_to, the id of the activity that should take the work back"},
      {:sunna_queue_block_refused,
       "a block may wait on another task's completion, never its own, never one that does not exist, and never close a loop of waits at any length",
       remedy: "name a different task, or give only a reason and clear it by hand"},
      {:sunna_queue_cutover, "the cutover happens once, and its revert only after it",
       remedy: "read the queue's state"},
      {:sunna_queue_dispatch_failed, "the house queue's command was not recorded",
       remedy: "try again; a repeat is a fault to report"},
      {:sunna_dispatch_failed, "the schedule's command was not recorded on its stream",
       remedy: "try again; a repeat is a fault to report"}
    ]
  end

  @impl Oneiroi.Component
  def children,
    do: [
      Oneiroi.Sunna.Projectors.Schedules,
      Oneiroi.Sunna.Projectors.Work,
      Oneiroi.Sunna.Projectors.Wakes,
      Oneiroi.Sunna.Projectors.Queue
    ]

  @doc "What a resident reports when the house checks in (sunna#65), by the house check-in's key; nil when not set."
  @spec house_prompt(String.t(), String.t()) :: String.t() | nil
  defexport(house_prompt(resident_id, key), do: Schedules.house_prompt(resident_id, key))

  @doc "Every house prompt a resident has, key to words (sunna#65)."
  @spec house_prompts(String.t()) :: %{String.t() => String.t()}
  defexport(house_prompts(resident_id), do: Schedules.house_prompts(resident_id))

  @doc "The witness sets a resident's words for a house check-in (sunna#65); blank clears."
  @spec set_house_prompt(String.t(), String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_house_prompt(resident_id, key, prompt, actor),
    do: Schedules.set_house_prompt(resident_id, key, prompt, actor)
  )

  @doc "The witness sets a resident's words and parts for a house check-in (sunna#68): `parts:` the catalog's keys."
  @spec set_house_prompt(String.t(), String.t(), String.t() | nil, Oneiroi.Actor.t(), keyword()) ::
          :ok | {:error, term()}
  defexport(set_house_prompt(resident_id, key, prompt, actor, opts),
    do: Schedules.set_house_prompt(resident_id, key, prompt, actor, opts)
  )

  @doc "A resident's parts for a house check-in (sunna#68), none when unset."
  @spec house_parts(String.t(), String.t()) :: [String.t()]
  defexport(house_parts(resident_id, key), do: Schedules.house_parts(resident_id, key))

  @doc "Every house check-in's parts for a resident, key to parts (sunna#68)."
  @spec house_parts_all(String.t()) :: %{String.t() => [String.t()]}
  defexport(house_parts_all(resident_id), do: Schedules.house_parts_all(resident_id))

  @doc "Sets a check-in (a fresh key when nil): label and HH:MM in the resident's zone; returns the key."
  @spec set_checkin(String.t(), String.t() | nil, String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(set_checkin(resident_id, key, label, time, actor),
    do: Schedules.set_checkin(resident_id, key, label, time, actor)
  )

  @doc "Sets a check-in with what its note carries (sunna#28): `parts:` from `CheckinParts.keys/0`, `prompt:` the witness's words; either left out keeps what it had."
  @spec set_checkin(
          String.t(),
          String.t() | nil,
          String.t(),
          String.t(),
          Oneiroi.Actor.t(),
          keyword()
        ) ::
          {:ok, String.t()} | {:error, term()}
  defexport(set_checkin(resident_id, key, label, time, actor, opts),
    do: Schedules.set_checkin(resident_id, key, label, time, actor, opts)
  )

  @doc "Deletes a check-in."
  @spec delete_checkin(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(delete_checkin(resident_id, key, actor),
    do: Schedules.delete_checkin(resident_id, key, actor)
  )

  @doc "Sets free time's slots, HH:MMs (one as a string is a list of one); it is never removed (sunna#21, #22), and either party may move it."
  @spec set_free_time(String.t(), [String.t()] | String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_free_time(resident_id, time, actor),
    do: Schedules.set_free_time(resident_id, time, actor)
  )

  @doc "Adds a one-off free-time slot (sunna#45): a time today or a day and time ahead, in her zone; either party; no cap."
  @spec add_free_time_once(String.t(), String.t() | nil, String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(add_free_time_once(resident_id, day, time, actor),
    do: Schedules.add_free_time_once(resident_id, day, time, actor)
  )

  @doc "The one-off free-time slots still ahead, in order (sunna#45)."
  @spec free_time_once(String.t()) :: [Oneiroi.Sunna.Store.FreeTimeOnce.t()]
  defexport(free_time_once(resident_id), do: Schedules.free_time_once(resident_id))

  @doc "The check-in that fired within ten minutes before `at`, or nil (brain#89)."
  @spec checkin_fired_before(String.t(), DateTime.t()) :: map() | nil
  defexport(checkin_fired_before(resident_id, at),
    do: Schedules.checkin_fired_before(resident_id, at)
  )

  @doc "A check-in's wake again, now (brain#89)."
  @spec retry_checkin(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(retry_checkin(resident_id, key, actor),
    do: Schedules.retry_checkin(resident_id, key, actor)
  )

  @doc "Free time now, under a one-off slot (brain#89)."
  @spec retry_free_time(String.t(), Oneiroi.Actor.t()) :: term()
  defexport(retry_free_time(resident_id, actor),
    do: Schedules.retry_free_time(resident_id, actor)
  )

  @doc "A thinking round now, under a one-off slot (brain#89)."
  @spec retry_round(String.t(), Oneiroi.Actor.t()) :: term()
  defexport(retry_round(resident_id, actor), do: Schedules.retry_round(resident_id, actor))

  @doc "The main chat woken now with the core's note (brain#89)."
  @spec wake_main_now(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(wake_main_now(resident_id, note, actor),
    do: Schedules.wake_main_now(resident_id, note, actor)
  )

  @doc "Records her plan for the next free-time slot (sunna#31), written in the planning turn."
  @spec plan_free_time(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(plan_free_time(resident_id, text, actor),
    do: Schedules.record_plan(resident_id, text, actor)
  )

  @doc "Her latest plan for free time (sunna#31): the text and when, or nil."
  @spec free_time_plan(String.t()) :: %{text: String.t(), at: DateTime.t()} | nil
  defexport(free_time_plan(resident_id), do: Schedules.plan(resident_id))

  @doc "Sets the resident's rounds (sunna#30): every_hours (0 off) and the waking window, nil for the default."
  @spec set_rounds(String.t(), non_neg_integer() | nil, String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_rounds(resident_id, every_hours, waking, actor),
    do: Schedules.set_rounds(resident_id, every_hours, waking, actor)
  )

  @doc "Adds an item to the work queue (sunna#33): what, and what done looks like; returns its number. The resident's and the witness's alike."
  @spec work_add(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(work_add(resident_id, what, done_when, actor),
    do: WorkLoop.add(resident_id, what, done_when, actor)
  )

  @doc "Moves a work item's status (open, blocked with what blocks it, done, dropped), with a note. Moving a held item clears its hold (sunna#55)."
  @spec work_move(
          String.t(),
          pos_integer(),
          String.t(),
          String.t() | nil,
          String.t(),
          Oneiroi.Actor.t()
        ) :: :ok | {:error, term()}
  defexport(work_move(resident_id, number, status, blocked_on, note, actor),
    do: WorkLoop.move(resident_id, number, status, blocked_on, note, actor)
  )

  @doc "Holds a work item for the witness (sunna#54): `ask` in plain words says what is needed of him; either party's, with an optional note."
  @spec work_hold(
          String.t(),
          pos_integer(),
          String.t() | nil,
          String.t() | nil,
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(work_hold(resident_id, number, ask, note, actor),
    do: WorkLoop.hold(resident_id, number, ask, note, actor)
  )

  @doc "Reorders the work queue: the numbers given first, in that order."
  @spec work_order(String.t(), [pos_integer()], Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(work_order(resident_id, numbers, actor),
    do: WorkLoop.order(resident_id, numbers, actor)
  )

  @doc "Her wrap of the running item: shipped, slipped, why, status, blocked_on, and ask when it is held (sunna#56)."
  @spec work_wrap(String.t(), pos_integer(), map(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(work_wrap(resident_id, number, attrs, actor),
    do: WorkLoop.wrap(resident_id, number, attrs, actor)
  )

  @doc "Arms the work line for a batch (sunna#35): the resident's act, by tool call."
  @spec work_arm(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(work_arm(resident_id, actor), do: WorkLoop.arm(resident_id, actor))

  @doc "Turns the work line off by hand (sunna#43): the witness's; the run in work finishes."
  @spec work_disarm(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(work_disarm(resident_id, actor), do: WorkLoop.disarm_by(resident_id, actor))

  @doc "Gives the day's work runs back (sunna#53): the witness's, with a note; the loop checks at once."
  @spec work_reset_runs(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(work_reset_runs(resident_id, note, actor),
    do: WorkLoop.reset_runs_by(resident_id, note, actor)
  )

  @doc "Skips the free-time wait (sunna#76): the witness's, with a note; the loop checks at once."
  @spec work_skip_care(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(work_skip_care(resident_id, note, actor),
    do: WorkLoop.skip_care_by(resident_id, note, actor)
  )

  @doc "The work queue: its items in order and the loop's state, both parties' read."
  @spec work_queue(String.t()) :: map()
  defexport(work_queue(resident_id), do: WorkLoop.queue(resident_id))

  # ---- the house queue (sunna#80) ----

  @doc "The house queue's starter templates by name (§7): copied into a household by `queue_define_template/4` with `from:`."
  @spec queue_starters() :: map()
  defexport(queue_starters(), do: Queues.starters())

  @doc "The household's members as the queue names them (`resident:<id>`, `witness:<id>`), with the house's name for each."
  @spec queue_members(String.t()) :: [map()]
  defexport(queue_members(household_id), do: Queues.members(household_id))

  @doc "Opens a project of the house queue: slug, name, owner."
  @spec queue_open_project(String.t(), map(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(queue_open_project(household_id, attrs, actor),
    do: Queues.open_project(household_id, attrs, actor)
  )

  @doc "Closes a project, with a note."
  @spec queue_close_project(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_close_project(household_id, slug, note, actor),
    do: Queues.close_project(household_id, slug, note, actor)
  )

  @doc "Defines a template (§7): title and layers, or `from:` a starter."
  @spec queue_define_template(String.t(), String.t(), map(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_define_template(household_id, name, attrs, actor),
    do: Queues.define_template(household_id, name, attrs, actor)
  )

  @doc "Opens a task from a template or layers, answering its number (`Queues.open_task/3`)."
  @spec queue_open_task(String.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(queue_open_task(household_id, attrs, actor),
    do: Queues.open_task(household_id, attrs, actor)
  )

  @doc "Takes an activity; `head:` the artifact's head read now."
  @spec queue_take(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t(), keyword()) ::
          :ok | {:error, term()}
  defexport(queue_take(household_id, task, act, actor, opts \\ []),
    do: Queues.take(household_id, task, act, actor, opts)
  )

  @doc "Finishes an activity: pin, head, result, note, and the copy a promotion made."
  @spec queue_finish(String.t(), pos_integer(), String.t(), map(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_finish(household_id, task, act, attrs, actor),
    do: Queues.finish(household_id, task, act, attrs, actor)
  )

  @doc "Skips an activity explicitly, with a note."
  @spec queue_skip(String.t(), pos_integer(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_skip(household_id, task, act, note, actor),
    do: Queues.skip(household_id, task, act, note, actor)
  )

  @doc "Blocks an activity with a reason, waiting on a task's completion when `waits_on` names one."
  @spec queue_block(
          String.t(),
          pos_integer(),
          String.t(),
          String.t(),
          pos_integer() | nil,
          Oneiroi.Actor.t()
        ) :: :ok | {:error, term()}
  defexport(queue_block(household_id, task, act, reason, waits_on, actor),
    do: Queues.block(household_id, task, act, reason, waits_on, actor)
  )

  @doc "Reopens a blocked or failed activity, with a note."
  @spec queue_reopen(String.t(), pos_integer(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_reopen(household_id, task, act, note, actor),
    do: Queues.reopen(household_id, task, act, note, actor)
  )

  @doc "Marks an activity failed, saying what failed."
  @spec queue_fail(String.t(), pos_integer(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_fail(household_id, task, act, what, actor),
    do: Queues.fail(household_id, task, act, what, actor)
  )

  @doc "Assigns an activity, with an optional note."
  @spec queue_assign(
          String.t(),
          pos_integer(),
          String.t(),
          String.t(),
          String.t() | nil,
          Oneiroi.Actor.t()
        ) :: :ok | {:error, term()}
  defexport(queue_assign(household_id, task, act, assignee, note, actor),
    do: Queues.assign(household_id, task, act, assignee, note, actor)
  )

  @doc "Decides a review: outcome, pin, head, return_to, withhold, note."
  @spec queue_decide(String.t(), pos_integer(), String.t(), map(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_decide(household_id, task, act, attrs, actor),
    do: Queues.decide(household_id, task, act, attrs, actor)
  )

  @doc "Fills a template's open artifact slot with its citation."
  @spec queue_fill_slot(String.t(), pos_integer(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_fill_slot(household_id, task, slot, artifact, actor),
    do: Queues.fill_slot(household_id, task, slot, artifact, actor)
  )

  @doc "Attaches a document to a task (sunna#91): role a slot name or source."
  @spec queue_attach_document(
          String.t(),
          pos_integer(),
          String.t(),
          String.t() | nil,
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(queue_attach_document(household_id, task, citation, role, actor),
    do: Queues.attach_document(household_id, task, citation, role, actor)
  )

  @doc "Detaches a document attached to a task (sunna#91)."
  @spec queue_detach_document(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_detach_document(household_id, task, citation, actor),
    do: Queues.detach_document(household_id, task, citation, actor)
  )

  @doc "Each task's documents by number (sunna#91): its activities' and those attached."
  @spec queue_documents(String.t(), [pos_integer()]) :: %{pos_integer() => [map()]}
  defexport(queue_documents(household_id, numbers), do: Queues.documents(household_id, numbers))

  @doc "The tasks a document belongs to (sunna#91), by its citation."
  @spec queue_tasks_for_document(String.t(), String.t()) :: [map()]
  defexport(queue_tasks_for_document(household_id, citation),
    do: Queues.tasks_for_document(household_id, citation)
  )

  @doc "Edits an open task's layers (sunna#85): existing activities by id, new ones as specs, with a note."
  @spec queue_edit_layers(String.t(), pos_integer(), list(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_edit_layers(household_id, task, layers, note, actor),
    do: Queues.edit_layers(household_id, task, layers, note, actor)
  )

  @doc "Drops a task, with a note; it counts as complete for what waits on it."
  @spec queue_drop(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_drop(household_id, task, note, actor),
    do: Queues.drop(household_id, task, note, actor)
  )

  @doc "Turns the house queue on (§6.2), naming the commit that holds the old one."
  @spec queue_cut_over(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_cut_over(household_id, commit, note, actor),
    do: Queues.cut_over(household_id, commit, note, actor)
  )

  @doc "Reverts the cutover in one step (§6.2)."
  @spec queue_cut_back(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(queue_cut_back(household_id, note, actor),
    do: Queues.cut_back(household_id, note, actor)
  )

  @doc "Pauses the house queue for every resident (sunna#94)."
  @spec queue_pause(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(queue_pause(household_id, note, actor), do: Queues.pause(household_id, note, actor))

  @doc "Lets the house queue run again (sunna#94)."
  @spec queue_resume(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(queue_resume(household_id, note, actor), do: Queues.resume(household_id, note, actor))

  @doc "The house queue's state: cut over and its commit."
  @spec queue_state(String.t()) :: Oneiroi.Sunna.QueueStore.State.t()
  defexport(queue_state(household_id), do: Queues.state(household_id))

  @doc "Whether the household has cut over to the house queue."
  @spec queue_cut_over?(String.t() | nil) :: boolean()
  defexport(queue_cut_over?(household_id), do: Queues.cut_over?(household_id))

  @doc "The household's projects."
  @spec queue_projects(String.t()) :: [Oneiroi.Sunna.QueueStore.Project.t()]
  defexport(queue_projects(household_id), do: Queues.projects(household_id))

  @doc "The household's templates."
  @spec queue_templates(String.t()) :: [Oneiroi.Sunna.QueueStore.Template.t()]
  defexport(queue_templates(household_id), do: Queues.templates(household_id))

  @doc "The tasks, open first; `project:` one project's."
  @spec queue_tasks(String.t(), keyword()) :: [Oneiroi.Sunna.QueueStore.Task.t()]
  defexport(queue_tasks(household_id, opts \\ []), do: Queues.tasks(household_id, opts))

  @doc "One task's page: the task, its layers, its history and what waits on it; nil when none."
  @spec queue_task(String.t(), pos_integer()) :: map() | nil
  defexport(queue_task(household_id, number), do: Queues.task(household_id, number))

  @doc "Activities by filter: who, views, project; each with its task and its blocker named."
  @spec queue_activities(String.t(), map()) :: [map()]
  defexport(queue_activities(household_id, filter \\ %{}),
    do: Queues.activities(household_id, filter)
  )

  @doc "Waiting on me (§2.2): ready first by what stands behind it, then the later and the owned."
  @spec queue_waiting_on(String.t(), String.t()) :: map()
  defexport(queue_waiting_on(household_id, who), do: Queues.waiting_on(household_id, who))

  @doc "A task's next action, or nil."
  @spec queue_next_action(String.t(), Oneiroi.Sunna.QueueStore.Task.t()) :: map() | nil
  defexport(queue_next_action(household_id, task), do: Queues.next_action(household_id, task))

  @doc "Sets quiet hours from HH:MM to HH:MM (may cross midnight), or both nil to clear."
  @spec set_quiet_hours(String.t(), String.t() | nil, String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_quiet_hours(resident_id, from, to, actor),
    do: Schedules.set_quiet_hours(resident_id, from, to, actor)
  )

  @doc "Whether the resident's quiet hours hold now, in her zone."
  @spec quiet_now?(String.t()) :: boolean()
  defexport(quiet_now?(resident_id), do: Schedules.quiet_now?(resident_id))

  @doc "Sets a date (a new row when number is nil): title, instant, kind; returns the number."
  @spec set_date(String.t(), pos_integer() | nil, map(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(set_date(resident_id, number, attrs, actor),
    do: Schedules.set_date(resident_id, number, attrs, actor)
  )

  @doc "Removes a date."
  @spec remove_date(String.t(), pos_integer(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(remove_date(resident_id, number, actor),
    do: Schedules.remove_date(resident_id, number, actor)
  )

  @doc "The latest free-time runs, newest first, each with its day, slot, outcome and the conversation it opened (sunna#25)."
  @spec free_time_history(String.t(), pos_integer()) :: [Oneiroi.Sunna.Store.FreeTimeRun.t()]
  defexport(free_time_history(resident_id, limit),
    do: Scope.resident(resident_id, fn -> Store.free_time_history(limit) end)
  )

  @doc "The latest rounds, newest first, each with its day, slot, outcome and the conversation it ran in (sunna#39)."
  @spec rounds(String.t(), pos_integer()) :: [Oneiroi.Sunna.Store.Round.t()]
  defexport(rounds(resident_id, limit),
    do: Scope.resident(resident_id, fn -> Store.rounds(limit) end)
  )

  @doc "The rounds claimed since an instant, oldest first (sunna#39)."
  @spec rounds_since(String.t(), DateTime.t()) :: [Oneiroi.Sunna.Store.Round.t()]
  defexport(rounds_since(resident_id, since),
    do: Scope.resident(resident_id, fn -> Store.rounds_since(since) end)
  )

  @doc "Today in the resident's zone: check-ins with firings, last and next, free time, quiet hours, dates with countdowns."
  @spec today(String.t()) :: map()
  defexport(today(resident_id), do: Schedules.today(resident_id))

  @doc "The dates section the brain reads, countdowns derived now; empty when none."
  @spec dates_text(String.t()) :: String.t()
  defexport(dates_text(resident_id), do: Schedules.dates_text(resident_id))

  @doc "A check-in note's parts, read for this resident now, in the catalog's order (sunna#28; sunna#68 for a house check-in's)."
  @spec checkin_part_texts(String.t(), [String.t()] | nil) :: [String.t()]
  defexport(checkin_part_texts(resident_id, parts),
    do: Schedules.part_texts(resident_id, parts)
  )

  @doc "Every firing over the last `days` days in the resident's zone, for the audits."
  @spec firings(String.t(), pos_integer()) :: [Oneiroi.Sunna.Store.Firing.t()]
  defexport(firings(resident_id, days), do: Schedules.firings(resident_id, days))

  @doc "The journal's day rows, newest first."
  @spec days(String.t(), pos_integer()) :: [Oneiroi.Sunna.Store.Day.t()]
  defexport(days(resident_id, limit), do: Schedules.days(resident_id, limit))

  @doc "A calendar range of her local days (sunna#48): `{:ok, %{from, to, today, zone, days}}`, or `sunna_day_invalid` / `sunna_range_invalid`."
  @spec days_range(String.t(), term(), term()) :: {:ok, map()} | {:error, term()}
  defexport(days_range(resident_id, from, to), do: Calendar.range(resident_id, from, to))

  @doc "The schedule the rules as they stand would run on each of `days` that is today or later (sunna#48): day to `%{quiet, rounds, entries}`."
  @spec day_schedules(String.t(), [String.t()]) :: %{String.t() => map()}
  defexport(day_schedules(resident_id, days), do: Calendar.schedules(resident_id, days))

  @doc "One day row, or nil."
  @spec day(String.t(), String.t()) :: Oneiroi.Sunna.Store.Day.t() | nil
  defexport(day(resident_id, day), do: Schedules.day(resident_id, day))

  @doc "Opens a day row the journal reached first (seshat#21); the schedule's row still, minted here."
  @spec open_day(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(open_day(resident_id, day, actor), do: Schedules.open_day(resident_id, day, actor))

  @doc "Runs one resident's tick now; what the minute job does for each."
  @spec tick(String.t()) :: :ok | :skipped
  defexport(tick(resident_id), do: TickWorker.tick(resident_id))

  @doc "Wakes a resident's Oneiroi chat for her household's beats, with the household's note (sunna#51)."
  @spec wake_for_household(String.t(), String.t(), Oneiroi.Actor.t(), String.t() | nil) ::
          {:ok, :woken} | {:error, term()}
  defexport(wake_for_household(resident_id, note, actor, wake_id \\ nil),
    do: Schedules.wake_for_household(resident_id, note, actor, wake_id)
  )

  @doc "Wakes a resident's chat for a house check-in, quiet hours aside (sunna#65)."
  @spec wake_for_house(String.t(), String.t(), Oneiroi.Actor.t(), String.t() | nil) ::
          {:ok, :woken} | {:error, term()}
  defexport(wake_for_house(resident_id, note, actor, wake_id \\ nil),
    do: Schedules.wake_for_house(resident_id, note, actor, wake_id)
  )

  @doc "Manifests a wake (sunna#71): its channel and what it carried; options `household_id`, `delivered`. Answers its id."
  @spec manifest_wake(String.t(), String.t(), [map()], keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(manifest_wake(resident_id, channel, causes, opts \\ []),
    do: Wakes.manifest(resident_id, channel, causes, opts)
  )

  @doc "The wake log of these residents (sunna#71), newest first: channel, causes, when manifested and read."
  @spec wakes([String.t()], pos_integer()) :: [map()]
  defexport(wakes(resident_ids, limit \\ 100), do: Wakes.list(resident_ids, limit))

  @doc "The marked hours, newest first (spec §6.7, P20 as amended): the pulse, one row per local hour the tick reached."
  @spec hours(String.t(), pos_integer()) :: [Oneiroi.Sunna.Store.Hour.t()]
  defexport(hours(resident_id, limit), do: Schedules.hours(resident_id, limit))

  @doc "The newest marked hour, or nil."
  @spec last_hour(String.t()) :: Oneiroi.Sunna.Store.Hour.t() | nil
  defexport(last_hour(resident_id), do: Schedules.last_hour(resident_id))

  @doc "Starts the memory backfill over `from..to` with the witness's and her domain slugs (sunna#59); `{:ok, days}`."
  @spec backfill_start(String.t(), String.t(), String.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defexport(backfill_start(resident_id, from, to, lists, actor),
    do: Backfill.start(resident_id, from, to, lists, actor)
  )

  @doc "Stops the memory backfill (sunna#59)."
  @spec backfill_stop(String.t()) :: :ok
  defexport(backfill_stop(resident_id), do: Backfill.stop(resident_id))

  @doc "Where the memory backfill is (sunna#59): the day and pass, the last day, the lists; nil when none runs."
  @spec backfill_status(String.t()) :: map() | nil
  defexport(backfill_status(resident_id), do: Backfill.status(resident_id))
end
