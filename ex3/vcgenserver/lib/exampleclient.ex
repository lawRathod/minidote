defmodule VCGenClient do

    def exampleUsage () do
        # Start the server
        {:ok, pid} = GenServer.start_link(VCGenServer, "Hello, World")

        # Send a message and expect a return value (sync)
        result1 = GenServer.call(pid, :pop)
        #=> "hello"

        # Send a message without return (async)
        :ok = GenServer.cast(pid, {:push, "elixir"})
        #=> :ok

        # Send another message and expect a return value (sync)
        result2 = GenServer.call(pid, :pop)
        #=> "elixir"
    end
end
