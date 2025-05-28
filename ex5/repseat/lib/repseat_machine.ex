
defmodule Repseat.Raft.Machine do
  require Record
  @behaviour :ra_machine

  # the state of the machine
  # keeps track of all
  # users, events, and the id of the latest event
  Record.defrecord(:state, users: %{}, events: %{}, max_event_id: 0)
  Record.defrecord(:user, name: "name", mail: "mail", password: "pass", balance: 0)
  Record.defrecord(:event, id: 0, person_limit: 0, price: 0, description: "desc", reservations: [], result: :not_started)

  ## @doc send a command to the ra node and waits for a result.
  ## if the ra node addressed isn't the leader and the leader is known
  ## it will automatically redirect the call to the leader node.
  ## This function returns after the command has been replicated and applied to
  ## the ra state machine. This is a fully synchronous interaction with the
  ## ra consensus system.
  ## Use this for low throughput actions where simple semantics are needed.
  ## if the state machine supports it it may return a result value which will
  ## be included in the result tuple.
  def send_and_await_consensus(node, request) do
    case :ra.process_command(node, request) do
      {:ok, reply, _Leader} -> reply
      other -> other
    end
  end



  ## @doc query the machine state on any node
  ## This allows you to run the QueryFun over the machine state and
  ## return the result. Any ra node can be addressed.
  ## This can return infinitely stale results.
  def local_query(node, read_fun) do
    {:ok, {_, res}, _} = :ra.local_query(node, read_fun)
    res
  end

  ## @doc Query the state machine
  ## This allows a caller to query the state machine by appending the query
  ## to the log and returning the result once applied. This guarantees the
  ## result is consistent.
  def consistent_query(node, readFunc) do
    case :ra.consistent_query(node, readFunc) do
      {:ok, {_, res}, _} -> res
      other -> other
    end
  end

  ## API FUNCTIONS

  ## Creates a new user with the given Name, Mail, and Password.
  ## Returns ':ok' when the user was created and {:error, :name_taken} if the user name is already taken.
  def create_user(node, name, mail, password) do
    send_and_await_consensus(node, {:add_user, name, mail, password})
  end

  def create_user(name, mail, password) do
    send_and_await_consensus({:node, node()}, {:add_user, name, mail, password})
  end

  ## Checks if there is a user with the given name and password combination
  ## Returns ok if password matches and {error, authentication_failed} otherwise
  def check_password(node, username, password) do
    raise "not implemented"
  end

  ## Creates a new event with the given description
  ## for which users can make a reservation.
  ## Each event gets assigned a new unique id,
  ## which is returned as {:ok, event_id}.
  def create_event(node, description, person_limit, price) do
    send_and_await_consensus(node, {:create_event, description, person_limit, price})
  end

  ## Makes the given user book a reservation for a given event.
  ## The cost of the reservation is subtracted from the user balance.
  ## Returns :ok if the reservation was successful
  ## Returns {:error, :invalid_user} or {error, invalid_event} if user or event does not exist
  ## Returns {:error, :insuffient_funds} if the users account balance is less than the Money he needs for the event cost
  ## Returns {:error, :invalied_event}, if event does not exist
  ## Returns {:error, :full}, if no more reservations are possible
  ## Returns {:error, :finished}, if the event has been completed and no more reservations are possible
  def book_event(node, username, event_id) do
    raise "not implemented"
  end

  ## Changes the balance of the given user by the given Amount
  ## Amount can be positive or negative, but the user account must always have positive value
  ## Returns :ok on success and {:error, :insufficient_funds}, if changing the balance would go below 0
  def change_balance(node, username, amount) do
    raise "not implemented"
  end

  ## Completes the given event.
  ## After completion, no more bookings are allowed.
  def complete_event(node, event_id) do
    raise "not implemented"
  end

  ## Completes the given event.
  ## After completion, no more bookings are allowed.
  ## In contrast to a finished event, the money is re-distributed
  ## amongst users.
  def cancel_event(node, event_id) do
    raise "not implemented"
  end

  ## Get a list of all event, that have not yet been completed
  ## Returns a list of tuples: {id, description, users}
  ## id is the Id of the challenge
  ## description is its description
  ## users all registered users
  def list_events(node) do
    raise "not implemented"
  end

  ## Get a list of all events, that the given user has participated in
  ## Returns a list of tuples: {id, description, price}
  ## id is the Id of the challenge
  ## description is its description
  ## price is the amount of money invested by the user
  def list_user_challenges(node, username) do
    raise "not implemented"
  end

  ## Get the current balance of a user
  ## Returns {:ok, balance} or {:error, :user_not_found}
  def get_balance(node, username) do
    raise "not implemented"
  end

  ## ra_machine callbacks:

  ## Init initializes the state machine
  ## Returns a initialState
  def init(_conf) do
    state()
  end

  ## Apply get's called when a command is sent to the state machine
  ## First argument is the Index of the Command
  ## Second argument is the command given in send_and_await_consensus
  ## Third argument is the current state
  ##
  ## Returns a tuple {newState, result, effects}
  def apply(_metadata, {:add_user, name, mail, password}, sstate) do
    {sstate, {:error, :name_taken}, []}
  end

  def leader_effects(_state) do [] end

  def eol_effects(_State) do [] end

  def tick(_State) do [] end

  def overview(_State) do %{} end

end
