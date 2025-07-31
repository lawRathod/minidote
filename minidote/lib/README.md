# Minidote Library Overview

Quick reference for reviewers to understand the library structure and module responsibilities without diving into implementation details.

## Architecture at a Glance

```
Client API (minidote.ex)
    ↓
Server Logic (minidote_server.ex) + Infrastructure (vector_clock.ex, broadcast_layer.ex, etc.)
    ↓
CRDT Types (crdt/*.ex) 
```

## Core Modules

### `minidote.ex` - Public API
Simple client interface for distributed CRDT operations:
- `read_objects/1,2` - Read CRDT values with optional causal consistency
- `update_objects/1,2` - Apply operations with automatic conflict resolution

### `minidote_server.ex` - Coordination Engine  
GenServer managing distributed state and consistency:
- CRDT object storage and versioning
- Vector clock management for causal ordering
- Effect broadcasting to other nodes
- Crash recovery with persistent logging

### `crdt.ex` - CRDT Behavior
Defines the interface all CRDT types implement:
- `new()`, `value()`, `downstream()`, `update()` callbacks
- Common utilities for CRDT operations

## CRDT Types (`crdt/`)

| Module | Type | Use Case | Conflict Resolution |
|--------|------|----------|-------------------|
| `counter_pn_ob.ex` | Counter | Metrics, tallies | Addition (commutative) |
| `counter_pn_sb.ex` | Counter (state-based) | Alternative counter impl | Lattice merge |
| `set_aw_ob.ex` | Add-Wins Set | Permissions, sessions | Add beats remove |
| `tpset_ob.ex` | Two-Phase Set | Permanent deletions | Remove is permanent |
| `mvreg_ob.ex` | Register | Single values | Last-writer-wins |
| `flag_ew_ob.ex` | Flag | Boolean toggles | Enable beats disable |

## Infrastructure

### `vector_clock.ex` - Causal Ordering
Tracks causal relationships between operations across nodes for consistency guarantees.

### `broadcast_layer.ex` - Message Distribution
Reliable delivery of CRDT effects to all nodes using process groups.

### `link_layer.ex` / `link_layer_distr.ex` - Network Transport
- `link_layer.ex`: Local/testing (no network)
- `link_layer_distr.ex`: Distributed Erlang nodes

### `consts.ex` - Configuration
System-wide constants for file paths, timeouts, and persistence settings.

## Key Design Decisions

**Operation-Based CRDTs**: Effects are broadcast, not full state (efficient network usage)

**Causal Consistency**: Vector clocks ensure operations are applied in causal order

**No Coordination**: No leader election or consensus - pure CRDT conflict resolution

**Crash Recovery**: Operation logging + state snapshots for fault tolerance

**OTP Integration**: Standard Elixir/OTP patterns with GenServer and supervision

## Data Flow Summary

1. **Updates**: Client → API → Server → Generate effects → Broadcast → Apply locally
2. **Reads**: Client → API → Server → Return current values + vector clock  
3. **Remote Effects**: Network → Broadcast Layer → Server → Apply → Update state
4. **Persistence**: All operations logged, periodic snapshots, replay on recovery

## For Code Reviewers

**Focus Areas**:
- CRDT conflict resolution logic in `crdt/*.ex`
- Causal consistency implementation in `minidote_server.ex`
- Vector clock operations in `vector_clock.ex`
- Network abstraction in broadcast/link layers

**Skip if Short on Time**:
- Detailed persistence mechanisms (well-established patterns)
- Configuration and constants (straightforward)
- Test setup and mocking (standard practices)

The core innovation is in the CRDT implementations and how they integrate with causal broadcast for distributed consistency without coordination.