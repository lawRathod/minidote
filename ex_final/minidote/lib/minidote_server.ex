defmodule Minidote.Server do
  use GenServer
  require Logger

  @moduledoc """
  The API documentation for `Minidote.Server`.
  """

  @impl true
  def init(_) do
    # FIXME the link layer should be initialized in the broadcast layer
    {:ok, _link_layer} = LinkLayerDistr.start_link(:minidote)
    # the state of the GenServer is: tuple of link_layer and respond_to
    {:ok, %{}}
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, :not_implemented, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unhandled info message: #{inspect msg}")
    {:noreply, state}
  end
end
