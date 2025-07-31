# Minidote Test Suite

Comprehensive test suite for the Minidote distributed CRDT system covering unit tests, integration tests, and end-to-end scenarios.

## Test Categories

### CRDT Unit Tests (`test/crdt/`)
- **Counters** (`counter_pn_*_test.exs`): Increment/decrement, merge behavior
- **Sets** (`set_aw_ob_test.exs`, `tpset_ob_test.exs`): Add-wins vs two-phase semantics
- **Registers** (`mvreg_ob_test.exs`): Multi-value assignment, concurrent resolution
- **Flags** (`flag_ew_ob_test.exs`): Enable-wins conflict resolution
- **Distributed** (`mvreg_distributed_test.exs`): Cross-node concurrent operations

### System Integration Tests
- **Vector Clocks** (`vector_clock_test.exs`): Causal ordering (15 tests)
- **Causal Broadcast** (`causal_broadcast_test.exs`): Message ordering (5 tests)
- **LinkLayer** (`linklayer_distributed_test.exs`): Node discovery, networking (4 tests)
- **Persistence** (`persistence_test.exs`): Crash recovery (2 tests)

### End-to-End Scenarios (`minidote_test.exs`)
1. **Collaborative Editing**: Document sync across 3 nodes
2. **E-commerce Cart**: Shopping cart + inventory management
3. **Feature Flags**: Enable-wins semantics validation
4. **Task Management**: Two-phase set workflow
5. **Crash Recovery**: Persistence and state recovery
6. **Social Platform**: 10-node scalability test

## Running Tests

```bash
mix test                              # All tests
mix test test/minidote_test.exs      # Specific file
mix test --trace                     # Verbose output
```

## Key Properties Tested

- **Causal Consistency**: Operations respect causal ordering via vector clocks
- **Eventual Consistency**: Nodes converge to same state when receiving same operations
- **CRDT Semantics**: Counter (commutative), Set_AW (add-wins), TPSet (tombstones), MVReg (last-writer-wins), Flag_EW (enable-wins)
- **Session Guarantees**: Read-your-writes consistency
- **Crash Recovery**: State persistence and recovery

## Test Stats
- **12 test files**, **~60 test cases**
- **6 CRDT types tested**
- **Up to 10 nodes** in scalability tests