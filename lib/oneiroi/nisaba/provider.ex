defmodule Oneiroi.Nisaba.Provider do
  @moduledoc """
  The provider port (spec §6.11, conventions §11): the one shape a model
  call has, with a real implementation over OpenRouter and an in-memory
  fake that ships with it, registered in `Oneiroi.Nisaba.externals/0`.

  Failures follow the three-way taxonomy of conventions §8. A refusal is
  not a failure: it is an ordinary result with `refusal?` set and the
  model's own words as `content`, shown as what it is (spec §5). A
  transport failure (`nisaba_provider_failed`) is retryable; a request the
  provider rejects as malformed or unauthorised (`nisaba_request_refused`)
  is cancelled. Both are sited `Oneiroi.Nisaba.Error`s built in the
  adapter, at the line that read the failure.
  """

  defmodule Usage do
    @moduledoc "What a call cost: tokens both ways and nano-dollars, marked when estimated rather than reported."
    @derive Jason.Encoder
    defstruct prompt_tokens: 0, completion_tokens: 0, cost_nanos: 0, estimated: false

    @type t :: %__MODULE__{
            prompt_tokens: non_neg_integer(),
            completion_tokens: non_neg_integer(),
            cost_nanos: non_neg_integer(),
            estimated: boolean()
          }
  end

  defmodule Request do
    @moduledoc """
    One chat completion request. Messages are maps with `:role`
    (`:system`, `:user`, `:assistant`, `:tool`) and `:content`; a system
    message's content comes from `Oneiroi.Nisaba.Prompt`, never from a
    literal (the `prompts` check). `tools` are OpenAI-shaped tool
    definitions, passed through for the brain.
    """
    @enforce_keys [:model]
    defstruct [:model, messages: [], max_tokens: nil, temperature: nil, tools: [], metadata: %{}]

    @type message :: %{required(:role) => atom(), required(:content) => String.t() | nil}
    @type t :: %__MODULE__{
            model: String.t(),
            messages: [message()],
            max_tokens: pos_integer() | nil,
            temperature: float() | nil,
            tools: [map()],
            metadata: map()
          }

    @doc "A request for `model` over `messages`, with the keyword options merged."
    @spec new(String.t(), [message()], keyword()) :: t()
    def new(model, messages, opts \\ []) when is_binary(model) and is_list(messages) do
      struct!(__MODULE__, Keyword.merge([model: model, messages: messages], opts))
    end
  end

  defmodule Result do
    @moduledoc "What came back: the text, the model that produced it, how it ended, and what it cost."
    @derive Jason.Encoder
    defstruct [
      :content,
      :model,
      :finish_reason,
      refusal?: false,
      tool_calls: [],
      usage: %Usage{}
    ]

    @type t :: %__MODULE__{
            content: String.t(),
            model: String.t() | nil,
            finish_reason: String.t() | nil,
            refusal?: boolean(),
            tool_calls: [map()],
            usage: Usage.t()
          }
  end

  defmodule Embedding do
    @moduledoc "What an embeddings call returned: one vector per input text, in order, the model, and what it cost."
    defstruct [:model, vectors: [], usage: %Usage{}]

    @type t :: %__MODULE__{model: String.t() | nil, vectors: [[float()]], usage: Usage.t()}
  end

  @type failure :: Oneiroi.Nisaba.Error.t()
  @type sink :: (String.t() -> any())

  @doc "Completes the request on the witness's key."
  @callback complete(Request.t(), key :: String.t()) :: {:ok, Result.t()} | {:error, failure()}

  @doc "Completes the request, calling `sink` with each delta of the reply as it arrives."
  @callback stream(Request.t(), key :: String.t(), sink()) ::
              {:ok, Result.t()} | {:error, failure()}

  @doc "Embeds the texts on the witness's key, one vector per text in order (spec §6.5: the library's index)."
  @callback embed(model :: String.t(), [String.t()], key :: String.t()) ::
              {:ok, Embedding.t()} | {:error, failure()}
end
