defmodule Phoenix.PubSub do

  @moduledoc """
  Serves as a Notification and PubSub layer for broad use-cases. Used internally
  by Channels for pubsub broadcast.

  ## PubSub Adapter Contract
  PubSub adapters need to only respond to a few process-based messages to
  integrate with Phoenix. PubSub functions send the following messages:

    * `subscribe` -
       sends:        `{:subscribe, pid, topic, link}`
       respond with: `:ok | {:error, reason} {:perform, {m, f a}}`

    * `unsubscribe` -
       sends:        `{:unsubscribe, pid, topic}`
       respond with: `:ok | {:error, reason} {:perform, {m, f a}}`

    * `subscribers` -
       respond with: `:ok | {:error, reason} {:perform, {m, f a}}`

    * `broadcast` -
       sends          `{:broadcast, :none, topic, message}`
       respond with: `:ok | {:error, reason} {:perform, {m, f a}}`


  ### Offloading work to clients via MFA response
  The `Phoenix.PubSub` API allows any of its functions to handle a
  response from the adapter matching `{:perform, {m, f a}}`. The PubSub
  client will recursively invoke all MFA responses until a result is
  return. This is useful for offloading work to clients without blocking
  in your PubSub adapter. See `Phoenix.PubSub.PG2` for an example usage.


  ## Example

      iex> PubSub.subscribe(self, "user:123")
      :ok
      iex> Process.info(self)[:messages]
      []
      iex> PubSub.subscribers("user:123")
      [#PID<0.169.0>]
      iex> PubSub.broadcast "user:123", {:user_update, %{id: 123, name: "Shane"}}
      :ok
      iex> Process.info(self)[:messages]
      {:user_update, %{id: 123, name: "Shane"}}

  """

  defmodule BroadcastError do
    defexception [:message]
    def exception(msg) do
      %BroadcastError{message: "Broadcast failed with #{inspect msg}"}
    end
  end


  @doc """
  Subscribes the pid to the pg2 group for the topic

    * `server` - The Pid registered name of the server
    * `pid` - The subscriber pid to receive pubsub messages
    * `topic` - The topic to subscribe to, ie: `"users:123"`
    * `opts` - The optional list of options. Supported options
               only include `:link` to link the subscriber to
               the pubsub adapter
  """
  def subscribe(server, pid, topic, opts \\ [])
  def subscribe(server, pid, topic, link: link),
    do: call(server, {:subscribe, pid, topic, link && true})
  def subscribe(server, pid, topic, _opts),
    do: call(server, {:subscribe, pid, topic, _link = false})

  @doc """
  Unsubscribes the pid from the pg2 group for the topic
  """
  def unsubscribe(server, pid, topic),
    do: call(server, {:unsubscribe, pid, topic})

  @doc """
  Returns lists of subscriber pids of members of pg2 group for topic
  """
  def subscribers(server, topic),
    do: call(server, {:subscribers, topic})

  @doc """
  Broadcasts message on given topic
  """
  def broadcast(server, topic, message),
    do: call(server, {:broadcast, :none, topic, message})

  @doc """
  Broadcasts message on given topic
  raises `Phoenix.PubSub.BroadcastError` if broadcast fails
  """
  def broadcast!(server, topic, message, broadcaster \\ __MODULE__) do
    case broadcaster.broadcast(server, topic, message) do
      :ok -> :ok
      {:error, reason} -> raise BroadcastError, message: reason
    end
  end

  @doc """
  Broadcasts message to all but sender on given topic
  """
  def broadcast_from(server, from_pid, topic, message),
    do: call(server, {:broadcast, from_pid, topic, message})

  @doc """
  Broadcasts message to all but sender on given topic
  raises `Phoenix.PubSub.BroadcastError` if broadcast fails
  """
  def broadcast_from!(server, from_pid, topic, message, broadcaster \\ __MODULE__) do
    case broadcaster.broadcast_from(server, from_pid, topic, message) do
      :ok -> :ok
      {:error, reason} -> raise BroadcastError, message: reason
    end
  end

  @doc false
  # Returns list of all topics under local server, for debug and perf tuning
  def list(server_name) do
    GenServer.call(Module.concat(server_name, Local), :list)
  end

  defp call(server, msg) do
    GenServer.call(server, msg) |> perform
  end

  defp perform({:perform, {mod, func, args}}) do
    apply(mod, func, args) |> perform
  end
  defp perform(result), do: result
end
