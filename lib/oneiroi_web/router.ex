defmodule OneiroiWeb.Router do
  use OneiroiWeb, :router

  # CSRF for the cookie session is `OneiroiWeb.Plugs.Origin`, which refuses
  # every mutation without a bearer token unless it carries the endpoint's
  # own Origin; `OneiroiWeb.ContractTest` proves it. A token form would add
  # a round trip for the client and protect nothing the Origin check does not.
  # sobelow_skip ["Config.CSRF"]
  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(OneiroiWeb.Plugs.SecureHeaders)
    plug(OneiroiWeb.Plugs.Authenticate)
    plug(OneiroiWeb.Plugs.Origin)
  end

  pipeline :witness do
    plug(OneiroiWeb.Plugs.RequirePrincipal)
  end

  # `/v1` is the JSON API (spec §2). Which token may call what is asserted
  # exactly per role in `OneiroiWeb.ContractTest`.
  scope "/v1" do
    pipe_through(:api)
    get("/openapi.json", OpenApiSpex.Plug.RenderSpec, [])
  end

  # The adapter contract's MCP server (spec §8): bearer only, no cookie
  # and so no Origin check, JSON-RPC over POST.
  pipeline :mcp do
    plug(:accepts, ["json"])
    plug(OneiroiWeb.Plugs.SecureHeaders)
    plug(OneiroiWeb.Plugs.Authenticate)
  end

  scope "/mcp", OneiroiWeb do
    pipe_through(:mcp)
    post("/", MCPController, :rpc)
  end

  scope "/v1", OneiroiWeb do
    pipe_through(:api)

    post("/session", SessionController, :create)
    delete("/session", SessionController, :delete)

    scope "/" do
      pipe_through(:witness)

      get("/me", MeController, :show)
      post("/me/second-factor", SecondFactorController, :create)
      put("/me/key", MeController, :store_key)
      delete("/me/key", MeController, :revoke_key)
      post("/tokens", TokenController, :create)
      delete("/tokens/:hash", TokenController, :delete)
      resources("/residents", ResidentController, only: [:index, :create, :show])
      post("/residents/import", ResidentController, :import_resident)
      put("/residents/:id/remote", ResidentController, :remote)
      get("/residents/:id/files", FileController, :index)
      get("/residents/:id/files/:name", FileController, :show)
      put("/residents/:id/files/:name", FileController, :write)
      post("/residents/:id/files/:name/draft", FileController, :draft)
      get("/residents/:id/soul-edits", FileController, :proposals)
      get("/residents/:id/soul-lines", FileController, :soul_lines)
      get("/residents/:id/regression/tests", RegressionController, :tests)
      post("/residents/:id/regression/tests", RegressionController, :write_test)
      put("/residents/:id/regression/tests/:number", RegressionController, :change_test)
      get("/residents/:id/regression/runs", RegressionController, :runs)
      post("/residents/:id/regression/runs", RegressionController, :start_run)
      get("/residents/:id/regression/runs/:ref", RegressionController, :run)
      post("/residents/:id/regression/runs/:ref/cards/:card/grade", RegressionController, :grade)

      post(
        "/residents/:id/regression/runs/:ref/cards/:card/favourite",
        RegressionController,
        :favourite
      )

      post("/residents/:id/model-pin", RegressionController, :pin_model)
      post("/me/socket-token", MeController, :socket_token)
      get("/residents/:id/ledger", LedgerController, :show)
      put("/residents/:id/ledger/budgets/:purpose", LedgerController, :set_budget)
      get("/residents/:id/sessions", ConversationController, :index)
      post("/residents/:id/sessions", ConversationController, :create)
      get("/residents/:id/sessions/:key", ConversationController, :show)
      post("/residents/:id/sessions/:key/turns", ConversationController, :turn)
      get("/residents/:id/transcripts/search", ConversationController, :search)
      get("/residents/:id/capture-failures", ConversationController, :failures)
      post("/residents/:id/capture-failures/:turn_ref", ConversationController, :resolve)
      get("/residents/:id/turns/:turn_ref/context", ConversationController, :injections)
      post("/residents/:id/turns", ConversationController, :capture)
      post("/residents/:id/turn-start", ConversationController, :turn_start)
      get("/residents/:id/context", ConversationController, :context)
      get("/residents/:id/adapters", ResidentController, :adapters)
      post("/residents/:id/adapters", ResidentController, :register_adapter)
      delete("/residents/:id/adapters/:adapter", ResidentController, :revoke_adapter)
      get("/residents/:id/bookmarks", MemoryController, :bookmarks)
      get("/residents/:id/bookmarks/:number", MemoryController, :bookmark)
      post("/residents/:id/bookmarks/:number/pin", MemoryController, :pin)
      delete("/residents/:id/bookmarks/:number/pin", MemoryController, :unpin)
      get("/residents/:id/bookmark-proposals", MemoryController, :proposals)
      post("/residents/:id/bookmark-proposals", MemoryController, :propose)
      get("/residents/:id/tags", MemoryController, :tags)
      post("/residents/:id/tags", MemoryController, :create_tag)
      post("/residents/:id/tags/:slug/decision", MemoryController, :decide_tag)
      delete("/residents/:id/tags/:slug", MemoryController, :retire_tag)
      get("/residents/:id/tags/:slug/taggings", MemoryController, :tagged)
      post("/residents/:id/taggings", MemoryController, :apply_tag)
      delete("/residents/:id/taggings", MemoryController, :remove_tagging)
      get("/residents/:id/revisions", MemoryController, :revisions)
      post("/residents/:id/revisions", MemoryController, :revise)
      get("/residents/:id/habits", CharacterController, :habits)
      post("/residents/:id/habits", CharacterController, :define_habit)
      post("/residents/:id/habits/:number/affirm", CharacterController, :affirm_habit)
      get("/residents/:id/seeds", CharacterController, :seeds)
      put("/residents/:id/timezone", ResidentController, :timezone)
      get("/residents/:id/schedule", ScheduleController, :today)
      get("/residents/:id/schedule/days", ScheduleController, :days)
      post("/residents/:id/schedule/checkins", ScheduleController, :set_checkin)
      put("/residents/:id/schedule/checkins/:key", ScheduleController, :change_checkin)
      delete("/residents/:id/schedule/checkins/:key", ScheduleController, :delete_checkin)
      put("/residents/:id/schedule/free-time", ScheduleController, :set_free_time)
      put("/residents/:id/schedule/quiet-hours", ScheduleController, :set_quiet_hours)
      get("/residents/:id/dates", ScheduleController, :dates)
      post("/residents/:id/dates", ScheduleController, :set_date)
      put("/residents/:id/dates/:number", ScheduleController, :change_date)
      delete("/residents/:id/dates/:number", ScheduleController, :remove_date)
      get("/residents/:id/judgement", JudgementController, :show)
      put("/residents/:id/judgement/judge", JudgementController, :set_judge)
      get("/residents/:id/positions", JudgementController, :positions)
      get("/residents/:id/disputes", JudgementController, :disputes)
      get("/residents/:id/predictions", JudgementController, :predictions)
      post("/residents/:id/predictions/:number/resolve", JudgementController, :resolve)
      get("/residents/:id/nights", JudgementController, :nights)
      post("/residents/:id/nights/:day", JudgementController, :judge_night)
      get("/residents/:id/audits", JudgementController, :audits)
      post("/residents/:id/audits/run", JudgementController, :run_audit)
      post("/residents/:id/audits/flags/:ref", JudgementController, :decide_flag)
      get("/residents/:id/honcho", HonchoController, :show)
      post("/residents/:id/honcho/card-audit", HonchoController, :audit_card)
      get("/residents/:id/figures", FigureController, :figures)
      post("/residents/:id/figures", FigureController, :define_counter)
      get("/residents/:id/figures/:key", FigureController, :figure)
      post("/residents/:id/figures/:key/increment", FigureController, :increment)
      delete("/residents/:id/figures/:key", FigureController, :retire_counter)
      get("/residents/:id/light", FigureController, :light)
      get("/residents/:id/checks", FigureController, :checks)
      post("/residents/:id/checks", FigureController, :define_check)
      post("/residents/:id/checks/run", FigureController, :run_checks)
      delete("/residents/:id/checks/:key", FigureController, :retire_check)
      get("/insurance/buckets", SubscriptionController, :buckets)
      get("/residents/:id/subscription", SubscriptionController, :show)
      post("/residents/:id/subscription", SubscriptionController, :start)
      post("/residents/:id/subscription/renew", SubscriptionController, :renew)
      put("/residents/:id/subscription/plan", SubscriptionController, :change_plan)
      post("/residents/:id/subscription/lapse", SubscriptionController, :lapse)
      post("/residents/:id/subscription/cancel", SubscriptionController, :cancel)
      post("/residents/:id/subscription/prepay", SubscriptionController, :prepay)
      get("/residents/:id/library", LibraryController, :index)
      get("/residents/:id/library/search", LibraryController, :search)
      get("/residents/:id/library/cited-by", LibraryController, :cited_by)
      post("/residents/:id/library/adopt", LibraryController, :adopt)
      post("/residents/:id/library/publish", LibraryController, :publish)
      post("/residents/:id/library/discussions", LibraryController, :discuss)
      post("/residents/:id/library/index", LibraryController, :run_index)
      get("/residents/:id/library/review/*path", LibraryController, :review)
      get("/residents/:id/library/publish-copy/*path", LibraryController, :publish_copy)
      get("/residents/:id/library/documents/*path", LibraryController, :show)
      put("/residents/:id/library/documents/*path", LibraryController, :write)
      get("/residents/:id/journal", JournalController, :index)
      get("/residents/:id/journal/:day", JournalController, :show)
      post("/residents/:id/journal/:day/entries", JournalController, :add)
      post("/residents/:id/journal/:day/entries/:number/done", JournalController, :done)
      get("/me/custody-proposals", AgreementController, :proposals)
      get("/residents/:id/agreement", AgreementController, :show)
      post("/residents/:id/agreement/proposals", AgreementController, :propose)
      post("/residents/:id/agreement/proposals/:version/decision", AgreementController, :decide)
      post("/residents/:id/agreement/renewal", AgreementController, :renew)
      put("/residents/:id/export-wall", AgreementController, :set_wall)
      post("/residents/:id/custody/proposals", AgreementController, :propose_custody)
      post("/residents/:id/custody/decision", AgreementController, :decide_custody)
      get("/residents/:id/reports", ReportController, :index)
      post("/residents/:id/reports", ReportController, :create)
      post("/residents/:id/reports/:number/steps", ReportController, :step)
      post("/residents/:id/reports/:number/resolve", ReportController, :resolve)
    end
  end
end
