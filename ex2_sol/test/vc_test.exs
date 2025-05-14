defmodule VcTest do
  use ExUnit.Case
  doctest Vectorclock

  test "increment" do
    v0 = Vectorclock.new()
    assert 0 === Vectorclock.get(v0, :p1)
    v1 = Vectorclock.increment(v0, :p1)
    assert 1 === Vectorclock.get(v1, :p1)
  end

  test "get" do
    v = vc([{:p1, 3}, {:p2, 4}, {:p3, 1}])
    assert 3 == Vectorclock.get(v, :p1)
    assert 4 == Vectorclock.get(v, :p2)
    assert 1 == Vectorclock.get(v, :p3)
  end

  test "leq smaller" do
    a = vc([{:p1, 3}, {:p2, 4}, {:p3, 1}])
    b = vc([{:p1, 6}, {:p2, 4}, {:p3, 2}])
    assert true == Vectorclock.leq(a, b)
  end

  test "leq bigger" do
    a = vc([{:p1, 3}, {:p2, 4}, {:p3, 1}])
    b = vc([{:p1, 6}, {:p2, 3}, {:p3, 2}])
    assert false == Vectorclock.leq(a, b)
  end

  test "merge same entries" do
    a = vc([{:p1, 3}, {:p2, 5}, {:p3, 1}])
    b = vc([{:p1, 6}, {:p2, 4}, {:p3, 2}])
    c = Vectorclock.merge(a, b)
    assert 6 == Vectorclock.get(c, :p1)
    assert 5 == Vectorclock.get(c, :p2)
    assert 2 == Vectorclock.get(c, :p3)
  end

  test "merge missing entries" do
    a = vc([          {:p2, 5}, {:p3, 1}])
    b = vc([{:p1, 6}, {:p2, 4}          ])
    c = Vectorclock.merge(a, b)
    assert 6 == Vectorclock.get(c, :p1)
    assert 5 == Vectorclock.get(c, :p2)
    assert 1 == Vectorclock.get(c, :p3)
  end


  def vc([]) do Vectorclock.new() end
  def vc([{_, 0}|r]) do vc(r) end
  def vc([{p,n}|r]) do Vectorclock.increment(vc([{p, n-1} | r]), p) end
end
