defmodule Snippets do

  # Question 1: What happens in this example? What does process B print?
  # Solution 1:
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
  # Solution 2:
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
  # Solution 3:
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
  # Solution 4:
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
