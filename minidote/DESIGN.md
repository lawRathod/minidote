# Minidote: High-Level System Design

This document provides a comprehensive overview of the Minidote distributed CRDT system's architecture, design principles, and key components.

## System Overview

Minidote is a distributed Conflict-free Replicated Data Type (CRDT) system built in Elixir that provides eventual consistency across multiple nodes without requiring coordination or consensus protocols. The system enables distributed applications to maintain consistency while being partition-tolerant and available.

### Core Principles

- **Eventual Consistency**: All nodes converge to the same state after network partitions heal
- **Causal Consistency**: Operations respect causal ordering using vector clocks
- **Partition Tolerance**: Continues operating during network partitions
- **Conflict-Free**: Deterministic conflict resolution built into data types

## Architecture Overview

```
┌─────────────────────────┐    ┌─────────────────────────┐    ┌─────────────────────────┐
│        Node A           │    │        Node B           │    │        Node C           │
├─────────────────────────┤    ├─────────────────────────┤    ├─────────────────────────┤
│   Minidote API          │    │   Minidote API          │    │   Minidote API          │
├─────────────────────────┤    ├─────────────────────────┤    ├─────────────────────────┤
│   Minidote.Server       │    │   Minidote.Server       │    │   Minidote.Server       │
│   - CRDT Storage        │    │   - CRDT Storage        │    │   - CRDT Storage        │
│   - Vector Clock        │    │   - Vector Clock        │    │   - Vector Clock        │
│   - Causal Ordering     │    │   - Causal Ordering     │    │   - Causal Ordering     │
├─────────────────────────┤    ├─────────────────────────┤    ├─────────────────────────┤
│   BroadcastLayer        │    │   BroadcastLayer        │    │   BroadcastLayer        │
├─────────────────────────┤    ├─────────────────────────┤    ├─────────────────────────┤
│   LinkLayer             │    │   LinkLayer             │    │   LinkLayer             │
├─────────────────────────┤    ├─────────────────────────┤    ├─────────────────────────┤
│   Persistence Layer     │    │   Persistence Layer     │    │   Persistence Layer     │
│   - Operation Log       │    │   - Operation Log       │    │   - Operation Log       │
│   - State Snapshots     │    │   - State Snapshots     │    │   - State Snapshots     │
└─────────────────────────┘    └─────────────────────────┘    └─────────────────────────┘
            │                             │                             │
            └─────────────────────────────┼─────────────────────────────┘
                                    Network Layer
                            (Causal Broadcast Messages)
```

## Key Components

### 1. Client API Layer

**Purpose**: Provides a clean, simple interface for applications

**Components**:
- `Minidote.read_objects/1,2`: Read CRDT values with optional causal consistency
- `Minidote.update_objects/1,2`: Apply operations to CRDTs

**Design Philosophy**:
- Hide distributed systems complexity from applications
- Simple key-value interface with CRDT semantics
- Automatic causal consistency management

### 2. CRDT Management Layer

**Purpose**: Core distributed state management and coordination

**Components**:
- `Minidote.Server`: GenServer managing CRDT objects and coordination
- Vector clock management for causal ordering
- Request queuing for causal dependency resolution
- Effect broadcasting for distributed updates

**Key Features**:
- **Object Storage**: Maps from keys to `{crdt_state, version}` tuples
- **Causal Consistency**: Vector clocks ensure proper operation ordering
- **Session Guarantees**: Read-your-writes and monotonic read consistency
- **Request Queuing**: Operations wait for causal dependencies before processing

### 3. CRDT Type System

**Purpose**: Provides conflict-free data types with different semantics

**Supported Types**:

#### Counter (Operation-Based & State-Based)
- **Use Case**: Metrics, tallies, distributed counting
- **Operations**: Increment, decrement
- **Conflict Resolution**: Addition is commutative and associative
- **Examples**: Page views, like counts, inventory quantities

#### Add-Wins Set  
- **Use Case**: Sets where additions are more important than removals
- **Operations**: Add, remove, add_all, remove_all, reset
- **Conflict Resolution**: Concurrent add wins over remove
- **Examples**: User permissions, feature flags, active sessions

#### Two-Phase Set
- **Use Case**: Sets requiring permanent deletion guarantees
- **Operations**: Add (once), remove (permanent)
- **Conflict Resolution**: Once removed, elements cannot be re-added
- **Examples**: Deleted users, revoked certificates, blacklists

#### Multi-Value Register
- **Use Case**: Single values with last-writer-wins semantics
- **Operations**: Assign value
- **Conflict Resolution**: Concurrent assignments preserved until causal order known
- **Examples**: User profiles, configuration values, document content

#### Enable-Wins Flag
- **Use Case**: Boolean flags where enabling takes precedence
- **Operations**: Enable, disable
- **Conflict Resolution**: Enable always wins over concurrent disable
- **Examples**: Feature toggles, maintenance modes, user account status

### 4. Distributed Communication

**Purpose**: Reliable message delivery with causal ordering

**Components**:

#### Vector Clock System
- **Functionality**: Tracks causal relationships between operations
- **Properties**: Detects concurrent vs. causally-ordered events
- **Usage**: Ensures operations are applied in causal order

#### Causal Broadcast Layer
- **Functionality**: Delivers messages in causal order to all nodes
- **Guarantees**: If A causally precedes B, then A is delivered before B
- **Implementation**: Uses process groups for receiver management

#### Link Layer
- **Local Mode**: Direct message passing for testing
- **Distributed Mode**: Real network communication between Erlang nodes
- **Features**: Network delay simulation, fault tolerance, auto-discovery

### 5. Persistence & Recovery

**Purpose**: Fault tolerance and crash recovery

**Components**:

#### Operation Logging
- **Technology**: Erlang Disk Log with wrap-around files
- **Purpose**: Persist all update operations for replay after crashes
- **Configuration**: Configurable file sizes and rotation limits

#### State Snapshots
- **Technology**: DETS (Disk-based Erlang Term Storage)
- **Purpose**: Periodic checkpoints to reduce recovery time
- **Strategy**: Snapshot at configurable intervals, prune old logs

#### Recovery Process
1. Load latest state snapshot
2. Replay operations from log since snapshot
3. Rebuild vector clocks and resume normal operation

## Data Flow & Operation Lifecycle

### Read Operations
```
1. Client calls Minidote.read_objects(keys, client_clock)
2. Server checks causal dependencies against client_clock
3. If ready: return current values immediately
4. If waiting: queue request until dependencies satisfied
5. Return values with updated vector clock
```

### Update Operations
```
1. Client calls Minidote.update_objects(updates, client_clock)
2. Server checks causal dependencies
3. Generate downstream effects from operations
4. Apply effects locally and update vector clock
5. Log operation to persistent storage
6. Broadcast effects to other nodes via BroadcastLayer
7. Return success with new vector clock
```

### Remote Effect Handling
```
1. Receive effect via causal broadcast
2. Check if effect can be delivered (causal dependencies met)
3. If ready: apply effect and update state
4. If waiting: buffer effect until dependencies satisfied
5. Check queued requests that might now be ready
```

## Consistency Model

### Causal Consistency
- **Property**: If operation A causally precedes B, A is seen before B on all nodes
- **Implementation**: Vector clocks track causal relationships
- **Benefits**: Intuitive consistency model respecting causality

### Session Guarantees
- **Read Your Writes**: Clients always see their own updates
- **Monotonic Reads**: Later reads never see older states than previous reads
- **Implementation**: Client vector clocks track causal dependencies

### Eventual Consistency
- **Property**: All nodes converge to same state when sharing the same operations
- **Mechanism**: CRDT conflict resolution ensures deterministic convergence
- **Limitation**: Operations that occur during network partitions may not be synchronized across all nodes

## Performance Characteristics

### Scalability
- **Node Count**: Tested up to 10 nodes, designed for larger deployments
- **Operation Throughput**: High throughput due to no coordination overhead
- **Storage**: Grows with operation history, mitigated by log pruning

### Network Efficiency
- **Message Size**: Compact downstream effects, not full state
- **Broadcast Overhead**: O(N) messages per update for N nodes
- **Optimization**: Batching and compression opportunities available

### Memory Usage
- **CRDT Storage**: Proportional to number of unique objects
- **Vector Clocks**: Small overhead (one counter per participating node)
- **Effect Buffering**: Temporary storage for out-of-order effects

## Use Cases & Applications

### Collaborative Applications
- **Document Editing**: Multi-user document collaboration
- **Real-time Chat**: Message synchronization across clients
- **Shared Whiteboards**: Concurrent drawing and editing

### Distributed Systems
- **Configuration Management**: Distributed configuration updates
- **Service Discovery**: Dynamic service registration and health status
- **Feature Flags**: Runtime feature toggle management

### IoT & Edge Computing
- **Sensor Networks**: Aggregating data from distributed sensors
- **Edge Synchronization**: Offline-first applications with sync
- **Device Management**: Managing state across IoT device fleets

### Gaming & Social Media
- **Player Statistics**: Distributed score and achievement tracking
- **Social Graphs**: Friend lists and social connections
- **Real-time Feeds**: Activity streams and timeline management

## Deployment Considerations

### Infrastructure Requirements
- **Erlang/OTP**: Requires Erlang virtual machine for distributed capabilities
- **Network**: TCP connectivity between all nodes
- **Storage**: Local disk space for operation logs and snapshots

### Configuration Options
- **Snapshot Intervals**: Balance between recovery time and storage
- **Log Rotation**: Configure based on operation volume and retention needs
- **Network Timeouts**: Adjust for network characteristics

### Monitoring & Observability
- **Vector Clock Inspection**: Monitor causal relationships and clock drift
- **Operation Metrics**: Track update rates and conflict frequency
- **Recovery Statistics**: Monitor crash frequency and recovery times

## Future Enhancements

### Performance Optimizations
- **Delta-State CRDTs**: Reduce network overhead with delta synchronization
- **Compression**: Compress operation logs and network messages
- **Batching**: Batch multiple operations for more efficient broadcasting
- **Partition healing**: After network is partitioned when nodes connect in future can sync opertiaons
- **Bootstrapping process**: Nodes on start should catchup to peers

### Additional CRDT Types
- **Sequence CRDTs**: For collaborative text editing (CRDT sequences)
- **Map CRDTs**: Nested CRDT structures with automatic conflict resolution
- **Graph CRDTs**: Distributed graph data structures

### Operational Features
- **Dynamic Membership**: Add/remove nodes without restart
- **Garbage Collection**: Advanced pruning strategies for long-running systems
- **Cross-Datacenter Replication**: Optimizations for WAN deployments

This design provides a solid foundation for building distributed applications that require strong consistency guarantees while maintaining availability during network partitions.