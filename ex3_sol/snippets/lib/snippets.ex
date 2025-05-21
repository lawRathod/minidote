defmodule Snippets do

  # Question 1: What happens in this example? What does process B print?
  # Solution 1: q1a sends its own pid to itself, on receiving it sends the increment by one function to q1b which executes it with the input of 3 => 3 + 1 = 4. The output is 4
  def q1setup() do
    # Process B
    pid_b = spawn(fn -> q1b() end)
    # Process A
    spawn(fn -> q1a(pid_b) end)
  end
  # A
  def q1a(pid_b) do
    send(self(), self())
    receive do
      _ -> send(pid_b , {:f, &(&1+1)})
    end
  end
  # B
  def q1b() do
    receive do
      {:f, f} -> IO.inspect(f.(3))
    end
  end


  # Question 2: What happens in this example? What do process C and D print? In what order?
  # Solution 2: Both processes are spawned and receive the others pid if they started in time (Process.alive?/0). When they  receive the pid they exchange 0 and 2. On receival they print the received values incremented by 1. The output is 1 and 3 in any order.
  def q2setup() do
    pid_c = spawn(fn -> q2c() end)
    pid_d = spawn(fn -> q2d() end)
    send(pid_c, {:pid, pid_d})
    send(pid_d, {:pid, pid_c})
  end
  # Process C
  def q2c() do
    receive do
      {:pid, pid_d} ->
        send(pid_d , {:n, 0})
        receive do
          {:n, n} -> IO.inspect(n+1)
        end
    end
  end
  # Process D
  def q2d() do
    receive do
      {:pid, pid_c} ->
        send(pid_c, {:n,2})
        receive do
          {:n, n} -> IO.inspect(n+1)
        end
    end
  end


  # Question 3: What happens in this example? What is the output? (You might want to save your progress beforehand and need to wait for some time if you execute this snippet)
  # Solution 3: q3e is started and waits for :pongs and prints :pong to the output stream as they are received. If q3e is started in time to receive the first send it will print :pong. Then 4 processes are spawned that fill up process E's mailbox with :ping messages that will never be matched until the memory overflows and the application crashes. It demonstrates the need for catch-all clauses in message passing.
  def q3setup() do
    pid_e = spawn(fn -> q3e() end)
    send(pid_e, :pong)
    spawn(fn -> q3f(pid_e) end)
    spawn(fn -> q3f(pid_e) end)
    spawn(fn -> q3f(pid_e) end)
    spawn(fn -> q3f(pid_e) end)
  end
  # Process E
  def q3e() do
    receive do
      :pong -> IO.inspect(:pong)
    end
    q3e()
  end
  # Process F
  def q3f(pid_e) do
    send(pid_e, :ping)
    q3f(pid_e)
  end


  # Question 4: What happens in this example? What is the output?
  # Solution 4: Processes G and H are created and linked to the creating process executing q4setup() and prints all relevant pids to the console. The same process then sends a message to process G who executes a faulty code path and crashes (^x=2) after outputting "I'm G". This error is propagated to the creating process since all three processes are linked. The creating process exits and causes process H to also be terminated.
  def q4setup() do
    pid_g = spawn_link(fn -> q4g() end)
    pid_h = spawn_link(fn -> q4h() end)
    IO.inspect(self())
    IO.inspect(pid_g)
    IO.inspect(pid_h)
    send(pid_g, :whoareyou)
    receive do
      _ -> IO.puts("I'm the setup. I think I forgot somebody")
    end
    pid_h
  end
  # Process G
  def q4g() do
    receive do
      _ -> IO.puts("I'm G"); x=1; ^x=2
    end
  end
  # Process H
  def q4h() do
    receive do
      _ -> IO.puts("I'm H")
    end
  end

end
