defmodule MVReg do
    use GenServer

    def new() do
        raise "not implemented"
    end

    def new(initial_value) do
        raise "not implemented"
    end

    def set(pid, element) do
        raise "not implemented"
    end

    def update(pid, update) do
        raise "not implemented"
    end

    @impl true
    def init(:ok) do
        raise "not implemented"
    end

    @impl true
    def handle_call({:set, element}, from, state) do
        raise "not implemented"
    end

    @impl true
    def handle_call({:update, update}, from, state) do
        raise "not implemented"
    end

end
