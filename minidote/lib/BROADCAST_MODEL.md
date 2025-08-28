# Broadcast Model for Distributed CRDTs

## Overview

Minidote implements a **causal broadcast system** for distributing CRDT operations across nodes in a cluster. The design ensures that CRDT operations are applied in causal order while maintaining high availability during network partitions.

## High-Level Architecture

```
Client Request → Minidote.Server → BroadcastLayer → LinkLayer → Remote Nodes
     ↓                  ↓              ↓             ↓
 Generate Effect   Log Locally    Reliable Send   Network Transport
```

### Core Components

1. **Minidote.Server**: Applies operations locally and generates downstream effects
2. **BroadcastLayer**: Handles causal ordering and reliable delivery to cluster members  
3. **LinkLayer**: Provides network abstraction with failure detection and retry logic
4. **Vector Clocks**: Track causal dependencies between operations across nodes

## Broadcast Protocol

### Operation Flow
1. **Local Application**: Operation applied to local CRDT state first
2. **Effect Generation**: Downstream effect computed for remote nodes
3. **Persistent Logging**: Effect logged to disk before broadcast (write-ahead logging)
4. **Causal Broadcast**: Effect sent to all nodes with vector clock timestamp
5. **Remote Application**: Receiving nodes apply effect respecting causal order

### Causal Ordering Mechanism
```elixir
# Effects include vector clock for causal ordering
{key, effect, from_node, effect_clock} = broadcast_message

# Receiving node checks causal dependencies
if VectorClock.ready_to_apply?(effect_clock, local_clock) do
  apply_effect(effect)
else
  queue_for_later(effect)  # Wait for dependencies
end
```

## Consistency Guarantees

### What Minidote Provides ✅

**Causal Consistency**: Operations that are causally related are applied in the same order on all nodes

**Eventual Convergence**: Nodes that receive the same set of operations converge to identical states

**Availability**: Nodes continue operating during network partitions

**CRDT Semantics**: Each data type maintains its mathematical properties (commutativity, associativity, idempotence)

### Design Limitations ❌

**No Anti-Entropy**: Missing operations during partitions are not synchronized when connectivity is restored

**No Bootstrap Protocol**: New nodes joining an existing cluster start with empty state

**No Byzantine Fault Tolerance**: Assumes nodes are honest but may crash or become partitioned

## Fault Tolerance Model

### Node Crashes
- **Recovery**: Operations logged before broadcast enable crash recovery via log replay
- **Persistence**: State snapshots + operation logs ensure durability

### Network Partitions  
- **During Partition**: Nodes operate independently, maintaining local consistency
- **After Partition**: Nodes reconnect automatically but do NOT synchronize missed operations
- **Implication**: Partitioned nodes may remain permanently diverged

### Message Loss
- **Link Layer**: Provides retry mechanisms for transient failures
- **Persistent Logs**: Operations survive node crashes but not permanent message loss between nodes

## Performance Characteristics

**Strengths**:
- No consensus overhead (unlike strong consistency protocols)
- High write availability during partitions
- Linear scalability for read operations

**Trade-offs**:
- Vector clock overhead grows with cluster size
- Permanent divergence possible after partitions

## Comparison to Standard Models

| Property | Minidote | Strong Consistency  |
|----------|----------|-------------------|
| Availability during partitions | ✅ | ❌ |
| Causal consistency | ✅ | ✅ |  
| Eventual convergence | ⚠️ (limited) | ✅ |
| Bootstrap new nodes | ❌ | ✅ |
