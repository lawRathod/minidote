defmodule Consts do
  @moduledoc """
  Constants and configuration values for the Minidote system.

  Centralizes important configuration values like file paths, intervals,
  and other system-wide constants.
  """

  @doc """
  Returns the base directory for persistence data storage.

  Data is stored relative to the project root in a 'data' directory,
  with subdirectories for each node.
  """
  @spec data_dir() :: String.t()
  def data_dir do
    project_root = File.cwd!()
    Path.join(project_root, "data")
  end

  @doc """
  Returns the data directory for a specific node.

  Each node gets its own subdirectory based on its name to avoid conflicts.

  ## Parameters

  - `node_name`: The node name (will be sanitized for filesystem use)

  ## Returns

  Path to the node-specific data directory.
  """
  @spec node_data_dir(String.t()) :: String.t()
  def node_data_dir(node_name) do
    sanitized_name = String.replace(node_name, "@", "_")
    Path.join(data_dir(), sanitized_name)
  end

  @doc """
  Returns the path for operation logs for a specific node.
  """
  @spec operation_log_path(String.t()) :: String.t()
  def operation_log_path(node_name) do
    Path.join(node_data_dir(node_name), "operations.log")
  end

  @doc """
  Returns the path for the DETS objects table for a specific node.
  """
  @spec objects_table_path(String.t()) :: String.t()
  def objects_table_path(node_name) do
    Path.join(node_data_dir(node_name), "objects.dets")
  end

  @doc """
  Default interval (in number of operations) between state snapshots.
  """
  @spec default_snapshot_interval() :: non_neg_integer()
  def default_snapshot_interval, do: 100

  @doc """
  Configuration for disk log files.

  Returns a tuple of `{max_file_size_bytes, max_files}`.
  """
  @spec disk_log_config() :: {non_neg_integer(), non_neg_integer()}
  # 1MB files, keep 10 files
  def disk_log_config, do: {1024 * 1024, 10}
end
