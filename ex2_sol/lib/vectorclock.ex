defmodule Vectorclock do
    # The map's key type for real processes would be "pid()" instead of atom()

    @spec new() :: %{atom() => integer()}
    def new() do
        %{}
    end

    @spec increment(%{atom() => integer()}, atom()) :: %{atom() => integer()}
    def increment(vc, p) do
       Map.update(vc, p, 1, fn count -> count + 1 end)
    end

    @spec get(%{atom() => integer()}, atom()) :: integer()
    def get(vc, p) do
        # Notice how we can provide a default value to hide missing entries
        Map.get(vc, p, 0)
    end

    # Additional function
    @spec eq(%{atom() => integer()}, %{atom() => integer()}) :: boolean()
    def eq(vc1, vc2) do
        vc1 === vc2
    end

    @spec leq(%{atom() => integer()}, %{atom() => integer()}) :: boolean()
    def leq(vc1, vc2) do
        # We need to only look at explicit keys of vc1
        # Are vc1's per key values less or equal to vc2's values?
        Enum.all?(vc1, fn {key, value1} -> value1 <= Map.get(vc2,key,0) end)
    end

    # https://hexdocs.pm/elixir/1.12/Map.html#merge/3
    @spec merge(%{atom() => integer()}, %{atom() => integer()}) :: %{atom() => integer()}
    def merge(vc1, vc2) do
        Map.merge(vc1, vc2, fn (_key, v1, v2) -> max(v1, v2) end)
    end

end
