defmodule VectorclockServer do
    # Hint: Check the slides: server process :)

    def start_link() do
        # start concurrent process listening for requests
        p = spawn_link(fn () -> loop(Vectorclock.new()) end)
        {:ok, p}
    end

    def loop(vectorclock) do
        newstate = receive do
            # Ping-pong test
            :ping -> IO.puts("pong!"); vectorclock
            {sender, :ping} -> send(sender, :pong); vectorclock

            # API
            {sender, :new} -> send(sender, Vectorclock.new()); vectorclock
            {sender, :increment} -> send(sender, incVec = Vectorclock.increment(vectorclock, sender)); incVec
            {sender, :get} -> send(sender, Vectorclock.get(vectorclock, sender)); vectorclock
            {sender, :leq, other_vc} -> send(sender, Vectorclock.leq(other_vc, vectorclock)); vectorclock
            {sender, :merge, other_vc} -> send(sender, Vectorclock.merge(other_vc, vectorclock)); vectorclock

            catch_all -> IO.inspect({"Unexpected message received: ", catch_all})
        end
        loop(newstate)
    end

end
