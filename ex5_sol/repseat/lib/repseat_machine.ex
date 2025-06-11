
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
    send_and_await_consensus(node, {:create_user, name, mail, password})
  end

  def create_user(name, mail, password) do
    send_and_await_consensus({:node, node()}, {:create_user, name, mail, password})
  end

  ## Checks if there is a user with the given name and password combination
  ## Returns ok if password matches and {error, authentication_failed} otherwise
  def check_password(node, username, password) do
    # NEW #
    send_and_await_consensus(node, {:check_password, username, password})
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
    # NEW #
    send_and_await_consensus(node, {:book_event, username, event_id})
  end

  ## Changes the balance of the given user by the given Amount
  ## Amount can be positive or negative, but the user account must always have positive value
  ## Returns :ok on success and {:error, :insufficient_funds}, if changing the balance would go below 0
  def change_balance(node, username, amount) do
    # NEW #
    send_and_await_consensus(node, {:change_balance, username, amount})
  end

  ## Completes the given event.
  ## After completion, no more bookings are allowed.
  def complete_event(node, event_id) do
    send_and_await_consensus(node, {:complete_event, event_id})
  end

  ## Completes the given event.
  ## After completion, no more bookings are allowed.
  ## In contrast to a finished event, the money is re-distributed
  ## amongst users.
  def cancel_event(node, event_id) do
    send_and_await_consensus(node, {:cancel_event, event_id})
  end

  ## Get a list of all event, that have not yet been completed
  ## Returns a list of tuples: {id, description, users}
  ## id is the Id of the challenge
  ## description is its description
  ## users all registered users
  def list_events(node) do
    send_and_await_consensus(node, {:list_events})
  end

  ## Get a list of all events, that the given user has participated in
  ## Returns a list of tuples: {id, description, price}
  ## id is the Id of the challenge
  ## description is its description
  ## price is the amount of money invested by the user
  def list_user_challenges(node, username) do
    send_and_await_consensus(node, {:list_user_challanges, username})
  end

  ## Get the current balance of a user
  ## Returns {:ok, balance} or {:error, :user_not_found}
  def get_balance(node, username) do
    send_and_await_consensus(node, {:get_balance, username})
  end

  ## ra_machine callbacks:

  ## Init initializes the state machine
  ## Returns a initialState
  def init(_conf) do
    state()
  end

  ## apply get's called when a command is sent to the state machine
  ## First argument is the Index of the Command
  ## Second argument is the command given in send_and_await_consensus
  ## Third argument is the current state
  ##
  ## Returns a tuple {newState, result, effects}
  def apply(_metadata, {:create_user, name, mail, password}, sstate) do
    if Map.has_key?(state(sstate, :users), name) do
      error(sstate, :name_taken)
    else
      update_state_user(
        user(name: name, mail: mail, password: password, balance: 0),
        sstate,
        :ok
      )
    end
  end

  def apply(_metadata, {:check_password, username, password},sstate) do
    user = get_user(sstate, username)
    IO.inspect(user)
    case user do
      {:user, _, _, ^password, _} -> {sstate, :ok, []}
      _ -> error(sstate, :authentication_failed)
      # {:user, _, _, _, _} -> error(sstate, :authentication_failed)
      # nil -> error(sstate, :name_unknown)
      # _ -> error(sstate, :unknown_error)
    end
  end

  def apply(_metadata, {:create_event, description, person_limit, price},sstate) do
    id = :erlang.unique_integer()
    update_state_event(
      event(id: id, person_limit: person_limit, price: price, description: description, reservations: [], result: :not_started),
      sstate,
      {:ok, id}
    )
  end

  def apply(_metadata, {:book_event, username, event_id}, sstate) do
    user = get_user(sstate,username)
    event = get_event(sstate, event_id)
    cond do
      user == nil -> error(sstate, :invalid_user)
      event == nil -> error(sstate, :invalied_event)
      true -> go_on_and_try_to_book_it_what_should_go_wrong_will_probably_be_great user, event, sstate
    end
  end

  def apply(_metadata, {:change_balance, username, amount}, sstate) do
    u_rec = get_user(sstate, username)
    cond do
      u_rec == nil -> error(sstate, :invalid_user)
      user(u_rec, :balance)-amount < 0 -> error(sstate, :insufficient_funds)
      true -> update_state_user(user(u_rec, balance: user(u_rec, :balance)+amount), sstate, :ok)
    end
  end

  def apply(_metadata, {:complete_event, event_id}, sstate) do
    e_rec = get_event(sstate, event_id)
    update_state_event(event(e_rec, result: :complete), sstate, :ok)
  end

  def apply(_metadata, {:cancel_event, event_id}, sstate) do
    e_rec = get_event(sstate, event_id)
    Enum.each(event(e_rec, :reservations), fn u ->  Repseat.Raft.Machine.apply(:wuii, {:change_balance, u, event(e_rec, :price)}, sstate)  end)
    update_state_event(event(e_rec, result: :canceled), sstate, :ok)
  end

  def apply(_metadata, {:list_events}, sstate) do
    uncompleted_events = Enum.filter(state(sstate, :events), fn e -> event(e, :result) != :complete end )
    mapped_events = Enum.map(uncompleted_events, fn {:event, id, _, _, desc, users, _} -> {id, desc, users} end)
    tuple_list = Enum.into(mapped_events, [])
    {sstate, {:ok, tuple_list}, []}
  end

  def apply(_metadata, {:list_user_challanges, username}, sstate) do
    u_rec = get_user(sstate, username)
    if u_rec == nil do
      error(sstate, :not_found)
    else
      completed_events = Enum.filter(state(sstate, :events), fn e -> event(e, :result) == :complete end )
      attended_events = Enum.filter(completed_events, fn e -> Enum.any?(event(e, :reservations), fn name -> name==username end ) end )
      mapped_events = Enum.map(attended_events, fn {:event, id, _, price, desc, _, _} -> {id, desc, price} end)
      tuple_list = Enum.into(mapped_events, [])
      {sstate, {:ok, tuple_list}, []}
    end
  end

  def apply(_metadata, {:get_balance, username}, sstate) do
    u_rec = get_user(sstate, username)
    if u_rec == nil do
      {sstate, {:error, :user_not_found}, []}
    else
      {sstate, {:ok, user(u_rec, :balance)}, []}
    end
  end


    # --- Helper ---

  def go_on_and_try_to_book_it_what_should_go_wrong_will_probably_be_great({:user, name, mail, password, balance}, {:event, id, person_limit, price, description, reservations, result}, sstate) do
    cond do
      length(reservations) == person_limit -> {sstate, {:error, :full}, []}
      balance < price -> error(sstate, :user_is_to_broke_to_have_fun)
      result != :not_started -> error(sstate, result)
      true -> update_state_both({:event, id, person_limit, price, description, [name] ++ reservations, result}, {:user, name, mail, password, balance - price}, sstate, {:ok, :book_event})
    end
  end

 def update_state_user(u_rec, sstate, return) do
    new_user_map = Map.put(state(sstate, :users),user(u_rec, :name), u_rec)
    {state(sstate, users: new_user_map), return, []}
  end

  def update_state_event(e_rec, sstate, return) do
    new_event_map = Map.put(state(sstate, :events),event(e_rec, :id), e_rec)
    {state(sstate, events: new_event_map), return, []}
  end

  def update_state_both(u_rec, e_rec, sstate, return) do
    new_user_map = Map.put(state(sstate, :users),user(u_rec, :name), u_rec)
    new_event_map = Map.put(state(sstate, :users),event(e_rec, :id), e_rec)
    {state(sstate, events: new_event_map, users: new_user_map), return, []}
  end

  def error(sstate, info) do
      {sstate, {:error, info}, []}
  end

  def get_user(sstate, name) do
    Map.get(state(sstate, :users), name)
  end

  def get_event(sstate, id) do
    Map.get(state(sstate, :events), id)
  end

  def leader_effects(_state) do [] end

  def eol_effects(_State) do [] end

  def tick(_State) do [] end

  def overview(_State) do %{} end

end
