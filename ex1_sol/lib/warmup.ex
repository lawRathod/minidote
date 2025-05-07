defmodule Warmup do

  @spec minimum(integer(), integer()) :: integer()
  def minimum(x, y) when x < y do x end
  def minimum(_, y) do y end





  @spec swap({}) :: {}
  @spec swap({X}) :: {X}
  @spec swap({X, Y}) :: {Y, X}
  @spec swap({X, Z, Y}) :: {Y, Z, X}
  @spec swap(tuple()) :: tuple()
  def swap({}) do {} end
  def swap({x}) do {x} end
  def swap({x, y}) do {y, x} end
  def swap({x, a, y}) do {y, a, x} end
  def swap(t) do
    [x | rest] = Tuple.to_list(t)
    [y | bodyr] = Enum.reverse(rest)
    body = Enum.reverse(bodyr)
    swapped = [y] ++ body ++ [x]
    List.to_tuple(swapped)
  end










  @spec only_integers?(any()) :: boolean()
  def only_integers?([]) do true end
  def only_integers?([x | rest]) when is_integer(x)
   do only_integers?(rest) end
  def only_integers?(_) do false end







  # @spec delete(atom(), list(tuple())) :: list(tuple())
  # @spec delete(atom(), list({atom(), term()})) :: list({atom(), term()})
  @spec delete(term(), [{term(), term()}]) :: [{term(), term()}]
  # TODO check why this does not work (Dialyzer)
  # @spec delete(Key, list({Key, Value})) :: list({Key, Value})
  # @spec delete(Key, [{Key, Value}]) :: [{Key, Value}]
  def delete(key, l) do
    {:ok, for {k,v} <- l, k != key do {k,v} end}
  end








  @spec same?(any(), any()) :: false
  def same?(x, y) do x === y end







  @spec same_ref?(any(), any()) :: boolean()
  def same_ref?(x, y) do :erts_debug.same(x, y) end








  @spec positive(list(number())) :: list(number())
  def positive(l) do Enum.filter(l, &(&1 >= 0)) end
  # def positive(l) do Enum.filter(l, fn x -> IO.inspect(:hello); x >= 0 end) end





  @spec all_positive?(list(number())) :: boolean()
  def all_positive?(l) do Enum.all?(l, &(&1 >= 0)) end






  @spec values(list({atom(), X})) :: list(X)
  def values(l) do Enum.map(l, fn {_,v} -> v end) end









  @spec list_min(nonempty_list(integer())) :: integer()
  def list_min([x | l] = big_list) do
   List.foldl(big_list, x, &(cond do &1 < &2 -> &1; true -> &2 end))
  end







  @spec fib(pos_integer()) :: pos_integer()
  def fib(1) do 1 end
  def fib(2) do 1 end
  def fib(n) do fib(n-1) + fib(n-2) end







  @spec fun1(boolean(), boolean()) :: number()
  def fun1(_, _) do 0 end

  @spec fun2(list({number, number}), any()) :: {{:notmatched, number()}, {:matched, number()}}
  def fun2(_, _) do {{:notmatched, 0}, {:matched, 0}} end

  @spec fun3(list(any()), atom()) :: list({atom(), any()})
  def fun3(_, _) do [] end

  @spec fun4([]) :: :error
  @spec fun4(list(X)) :: X
  @spec fun4(list(list(X))) :: list(X)
  def fun4([]) do :error end
  def fun4([x]) do x end
  def fun4([x | [ y | ys]]) do x ++ fun4([y | ys]) end


end
