defmodule EvercamMedia.Snapshot.Deletion do
  @moduledoc """
  Provides functions and workers for deleting cloud recording

  """

  use GenStage
  require Logger
  alias EvercamMedia.Snapshot.Storage

  ################
  ## Client API ##
  ################

  @doc """
  Start a deletion for camera.
  """
  def start_link(args) do
    GenStage.start_link(__MODULE__, args)
  end

  @doc """
  Get the configuration of the camera deletion.
  """
  def get_config(cam_server) do
    GenStage.call(cam_server, :get_deletion_config)
  end

  @doc """
  Update the configuration of the camera worker
  """
  def update_config(cam_server, config) do
    GenStage.cast(cam_server, {:update_camera_config, config})
  end


  ######################
  ## Server Callbacks ##
  ######################

  @doc """
  Initialize the camera server
  """
  def init(args) do
    args = Map.merge args, %{
      timer: start_timer(:delete)
    }
    {:consumer, args}
  end

  def handle_cast({:update_camera_config, new_config}, state) do
    {:ok, timer} = Map.fetch(state, :timer)
    :erlang.cancel_timer(timer)
    new_timer = start_timer(:delete)
    new_config = Map.merge new_config, %{
      timer: new_timer
    }
    {:noreply, [], new_config}
  end

  @doc """
  Server callback for getting camera deletion state
  """
  def handle_call(:get_deletion_config, _from, state) do
    {:reply, state, [], state}
  end

  @doc """
  Server callback for deleting
  """
  def handle_info(:delete, state) do
    {:ok, timer} = Map.fetch(state, :timer)
    :erlang.cancel_timer(timer)

    Logger.debug "start deletion for camera: #{state.name}"
    state.config.camera_id
    |> CloudRecording.by_camera_id
    |> Storage.cleanup

    state.config.camera_id
    |> Storage.delete_response_info

    timer = start_timer(:delete)
    {:noreply, [], Map.put(state, :timer, timer)}
  end

  @doc """
  Take care of unknown messages which otherwise would trigger function clause mismatch error.
  """
  def handle_info(msg, state) do
    Logger.info "[handle_info] [#{msg}] [#{state.name}] [unknown messages]"
    {:noreply, [], state}
  end

  #######################
  ## Private functions ##
  #######################

  defp start_timer(message) do
    Process.send_after(self(), message, 1000 * 60 * 60)
  end
end
