# Minidote - Distributed CRDT System

Minidote is an Elixir implementation of a distributed CRDT (Conflict-free Replicated Data Type) system that provides eventual consistency across multiple nodes with causal broadcast guarantees.

## CRDT Types Supported

- **Counter_PN_OB**: Increment/decrement counter with operation-based semantics
- **Counter_PN_SB**: Increment/decrement counter with state-based semantics
- **Set_AW_OB**: Add-wins set where additions beat concurrent removals
- **MVReg_OB**: Multi-value register preserving concurrent assignments
- **TPSet_OB**: Two-phase set with permanent removals
- **Flag_EW_OB**: Enable-wins flag where enable beats concurrent disable

## Architecture

The system consists of several key components:

- **Minidote.Server**: Main GenServer handling CRDT operations and state management
- **BroadcastLayer**: Causal broadcast implementation for distributed effects
- **LinkLayer**: Network abstraction with failure detection and retry logic
- **Vector Clocks**: Causal ordering mechanism for distributed operations
- **CRDT Modules**: Individual CRDT type implementations

## Documentation

### Core Documentation

- **[DESIGN.md](DESIGN.md)**: High-level system architecture and design decisions
- **[lib/README.md](lib/README.md)**: Module responsibilities and CRDT implementation details
- **[lib/BROADCAST_MODEL.md](lib/BROADCAST_MODEL.md)**: Causal broadcast protocol and consistency guarantees
- **[test/README.md](test/README.md)**: Testing infrastructure and comprehensive test scenarios

### Key Features

- **Causal Consistency**: Operations applied in causal order using vector clocks
- **High Availability**: Continues operating during network partitions
- **Crash Recovery**: Persistent logging with operation replay on restart
- **Multiple Node Support**: Tested with up to 10 distributed nodes
- **Real-world Scenarios**: Comprehensive tests including social media platform simulation

### Limitations

- **No Anti-Entropy**: Missing operations during partitions are not synchronized
- **No Bootstrap Protocol**: New nodes start with empty state
- **Permanent Divergence**: Nodes may remain inconsistent after partitions

## Testing

The project includes comprehensive distributed system tests:

```bash
# Run all tests
mix test

# Run all real world inspired testing scenarios
mix test test/minidote_test.exs
```

Test scenarios include:

- Basic CRDT operations across multiple nodes
- Crash recovery with persistent logs
- 10-node social media platform simulation
- Vector clock causal ordering validation

## Running minidote

To try or run this project please refer [cli guide doc](CLI_GUIDE.md) with one of the test scenerio from [minidote_test.exs](test/minidote_test.exs).

## AI Usage

This project was developed with AI assistance:

### AI Tools Used
- **Claude Code**: Primary development assistant for code implementation and debugging through cli
- **Windsurf**: Additional programming support through text editor
