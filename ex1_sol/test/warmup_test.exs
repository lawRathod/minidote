defmodule WarmupTest do
  use ExUnit.Case

	test "minimum test" do
		assert Warmup.minimum(3,7) == 3
		assert Warmup.minimum(5,4) == 4
		assert Warmup.minimum(0,2) == 0
	end


	test "swap test" do
		assert Warmup.swap({100, :ok}) == {:ok, 100}
		assert Warmup.swap({100, 200, :ok}) == {:ok, 200, 100}
		assert Warmup.swap({:ok}) === {:ok}
		assert Warmup.swap({}) === {}
	end

	test "delete test" do
		assert Warmup.delete(:helo, [{:helo, 1}, {:world, 2}]) == {:ok, [{:world, 2}]}
	end


	test "onlyints test" do
		assert Warmup.only_integers?([4,7,2]) == true
		assert Warmup.only_integers?([2,4,5.0,7]) == false
	end


	test "positive test" do
		assert [6, 3, 0] == Warmup.positive([6, -5, 3, 0, -2])
	end

	test "all positive test" do
		assert true == Warmup.all_positive?([1,2,3])
		assert false == Warmup.all_positive?([1,-2,3])
	end

	test "values test" do
		assert [5, 7, 3, 1] == Warmup.values([{:c, 5}, {:z, 7}, {:d, 3}, {:a, 1}])
	end

	test "minimum list test" do
		assert 2 == Warmup.list_min([7, 2, 9])
	end

end
