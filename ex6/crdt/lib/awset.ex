defmodule AWSet do
    use GenServer

    def new() do
        raise "not implemented"
    end

    def new(initial_set) do
        raise "not implemented"
    end

    def add(element) do
        raise "not implemented"
    end

    def delete(element) do
        raise "not implemented"
    end

    def update(update) do
        raise "not implemented"
    end

    @impl true
    def init(:ok) do
        raise "not implemented"
    end

    @impl true
    def handle_call({:add, element}, from, state) do
        raise "not implemented"
    end

    @impl true
    def handle_call({:delete, element}, from, state) do
        raise "not implemented"
    end

    @impl true
    def handle_call({:update, update}, from, state) do
        raise "not implemented"
    end

end
