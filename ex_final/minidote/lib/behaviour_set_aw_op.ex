defmodule Set_AW_OP do
  @behaviour CRDT

  @moduledoc """
  Documentation for `Set_AW_OP`.

  An operation-based Observed-Remove Set CRDT.

  Reference papers:
  Marc Shapiro, Nuno Preguiça, Carlos Baquero, Marek Zawirski (2011)
  A comprehensive study of Convergent and Commutative Replicated Data Types
  """

  # ToDo: Add type spec
  @type t :: :set_aw_op

  def new() do
    raise "implement"
  end

  def value(state) when is_integer(pn_state) do
    raise "implement"
  end

  def downstream(_,_) do
    raise "implement"
  end

  def update(effect, state) do
    raise "implement"
  end

  def equal(state1, state2) do
    raise "implement"
  end

  # all operations require state downstream
  def require_state_downstream({add, _}) do true end
  def require_state_downstream({add_all, _}) do true end
  def require_state_downstream({remove, _}) do true end
  def require_state_downstream({remove_all, _}) do true end
  def require_state_downstream({reset, {}}) do true end

end
