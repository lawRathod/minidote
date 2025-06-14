defmodule TPSet do
    use GenServer

    def new() do
        raise "not implemented"
        {pid, app_view}
    end

    def new(initial_set) do
        {:ok, pid} = GenServer.start(TPSet, {initial_set, MapSet.new()})
        raise "not implemented"
        {pid, app_view}
    end

    def add(pid, element) do
        update = GenServer.call(pid, {:add, element})
    end

    def delete(pid, element) do
        update = GenServer.call(pid, {:delete, element})
    end

    def update(pid, update) do
        app_view = GenServer.call(pid, {:update, update})
    end

    @impl true
    def init({added_set, deleted_set}) do
        raise "not implemented"
        {:ok, initial_state}
    end

    @impl true
    def handle_call({:add, element}, from, state = {added_set, deleted_set}) do
        raise "not implemented"
        {:reply, _update = {add_update, deleted_set}, state}
    end

    @impl true
    def handle_call({:delete, element}, from, state = {added_set, deleted_set}) do
        raise "not implemented"
        {:reply, _update = {added_set, del_update}, state}
    end

    @impl true
    def handle_call({:update, update = {up_add, up_del}}, from, {added_set, deleted_set}) do
        raise "not implemented"
        {:reply, app_view, _state = {new_added, new_deleted}}
    end
end
