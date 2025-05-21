defmodule VCGenClient do

    def eg1() do
        IO.inspect("Start the server")
        {:ok, pid} = GenServer.start_link(VCGenServer, %{})
        IO.inspect("#{inspect({:ok, pid})} = GenServer.start_link(VCGenServer, %{})")

        IO.inspect("Increment own counter")
        result1 = GenServer.call(pid, :increment)
        IO.inspect("#{inspect(result1)} = GenServer.call(VCGenServer, :increment)")

        IO.inspect("Increment own counter")
        result2 = GenServer.call(pid, :increment)
        IO.inspect("#{inspect(result2)} = GenServer.call(VCGenServer, :increment)")

        IO.inspect("Increment own counter")
        result3 = GenServer.call(pid, :increment)
        IO.inspect("#{inspect(result3)} = GenServer.call(VCGenServer, :increment)")

        IO.inspect("Get VC")
        result4 = GenServer.call(pid, :get)
        IO.inspect("#{inspect(result4)} = GenServer.call(pid, :get)")

        IO.inspect("Increment own counter")
        result5 = GenServer.call(pid, :increment)
        IO.inspect("#{inspect(result5)} = GenServer.call(VCGenServer, :increment)")

        IO.inspect("Local VC LEQ")
        result6 = GenServer.call(pid, {:leq, result4})
        IO.inspect("#{inspect(result6)} = GenServer.call(pid, {:leq, result4 = #{inspect(result4)}})")

        IO.inspect("Merge VC")
        spawn_link(fn -> GenServer.call(pid, :increment); GenServer.call(pid, :increment); GenServer.call(pid, :increment) end)
        spawn_link(fn -> GenServer.call(pid, :increment); GenServer.call(pid, :increment) end)
        spawn_link(fn -> GenServer.call(pid, :increment) end)
        result7 = GenServer.cast(pid, {:merge, result4})
        IO.inspect("#{inspect(result7)} = GenServer.cast(pid, {:merge, result4 = #{inspect(result4)}})")

        IO.inspect("Get own counter")
        result8 = GenServer.call(pid, {:get, self()})
        IO.inspect("#{inspect(result8)} = GenServer.call(pid, {:get, self() = #{inspect(self())}})")

        IO.inspect("Get VC")
        result4 = GenServer.call(pid, :get)
        IO.inspect("#{inspect(result4)} = GenServer.call(pid, :get)")

    end
end
