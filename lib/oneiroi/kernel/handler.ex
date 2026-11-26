defmodule Oneiroi.Handler do
  @moduledoc """
  What a system's event handler adopts in place of Commanded's own
  (conventions §7): `use Oneiroi.Handler, application: ..., name: ...,
  consistency: ...`, every option Commanded's takes, and one of its own.

  A handler does something (joins a resident to a household, files a
  triage row, queues an index); a projector only folds. When a
  resident's life is moved under another id, byte for byte, its events
  are appended again (`Oneiroi.SimaQian.Transplant`: a succession's fork
  and its cutover), and every handler sees them as new. Projectors must
  fold them; a handler must not act on them, or a fork joins the house
  as a second her, and a cutover does again whatever her history once
  did. So every handler passes over an event whose metadata marks it
  `transplanted`, in front of its own `handle/2`, unless it says
  `replays: true` (sima-qian#69). The guard is written once, here, never
  in each handler; a test holds every handler in `lib/` to this macro.
  """

  defmacro __using__(opts) do
    {replays, opts} = Keyword.pop(opts, :replays, false)

    quote do
      use Commanded.Event.Handler, unquote(opts)
      @oneiroi_handler_replays unquote(replays)
      @before_compile Oneiroi.Handler
    end
  end

  defmacro __before_compile__(env) do
    if Module.get_attribute(env.module, :oneiroi_handler_replays) do
      quote do
        @doc false
        def __replays__, do: true
      end
    else
      quote do
        defoverridable handle: 2

        @impl Commanded.Event.Handler
        def handle(event, metadata) do
          if Oneiroi.Handler.transplanted?(metadata),
            do: :ok,
            else: super(event, metadata)
        end

        @doc false
        def __replays__, do: false
      end
    end
  end

  @doc "Whether an event was appended by a transplant (a fork, a cutover), not by its own command."
  @spec transplanted?(map() | nil) :: boolean()
  def transplanted?(%{"transplanted" => true}), do: true
  def transplanted?(_metadata), do: false
end
