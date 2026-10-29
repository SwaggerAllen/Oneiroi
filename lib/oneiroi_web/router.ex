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

  pipeline :steward do
    plug(OneiroiWeb.Plugs.RequirePrincipal)
  end

  # `/v1` is the JSON API (spec §2). Which token may call what is asserted
  # exactly per role in `OneiroiWeb.ContractTest`.
  scope "/v1" do
    pipe_through(:api)
    get("/openapi.json", OpenApiSpex.Plug.RenderSpec, [])
  end

  scope "/v1", OneiroiWeb do
    pipe_through(:api)

    post("/session", SessionController, :create)
    delete("/session", SessionController, :delete)

    scope "/" do
      pipe_through(:steward)

      get("/me", MeController, :show)
      post("/me/second-factor", SecondFactorController, :create)
      put("/me/key", MeController, :store_key)
      delete("/me/key", MeController, :revoke_key)
      post("/tokens", TokenController, :create)
      delete("/tokens/:hash", TokenController, :delete)
      resources("/residents", ResidentController, only: [:index, :create, :show])
      put("/residents/:id/remote", ResidentController, :remote)
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
    end
  end
end
