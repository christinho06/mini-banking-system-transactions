# Mini Banking System - Transaction Flow and Distribution Planning

## Part 1 - Transaction Management (Conceptual)

### Concurrency Issue Identified: Lost Update Problem

When two users simultaneously transfer money involving the same account (e.g., Account A), a **lost update** can occur:

**Scenario:**
- Transaction T1: Transfer $200 from Account A → Account B
- Transaction T2: Transfer $150 from Account A → Account C
- Both read Account A balance = $1000 simultaneously
- T1 writes: $1000 - $200 = $800
- T2 writes: $1000 - $150 = $850 (overwriting T1's update)
- Final balance = $850 (incorrect — should be $650)

### Locking Mechanism Proposed: Two-Phase Locking (2PL) with Strict Mode

**Strict Two-Phase Locking (S2PL):**
1. **Growing Phase**: A transaction acquires all needed locks (shared for reads, exclusive for writes) before performing operations.
2. **Shrinking Phase**: All locks are released only after the transaction commits or rolls back.

**Lock Types Used:**
- `SHARED (S)`: For reading account balances
- `EXCLUSIVE (X)`: For updating account balances (debit/credit)

**Protocol:**
```
BEGIN TRANSACTION;
LOCK TABLE accounts IN ROW EXCLUSIVE MODE;
SELECT balance FROM accounts WHERE id = :source_id FOR UPDATE;
SELECT balance FROM accounts WHERE id = :dest_id FOR UPDATE;
-- Perform debit/credit
UPDATE accounts SET balance = balance - :amount WHERE id = :source_id;
UPDATE accounts SET balance = balance + :amount WHERE id = :dest_id;
COMMIT;  -- Releases all locks
```

**Deadlock Prevention:**
- Enforce a consistent lock ordering (always lock accounts by ascending ID)
- Use timeout-based deadlock detection: abort transaction if lock wait > 5 seconds

---

## Part 2 - Distribution Planning

### Banking System Distribution Design

The banking system serves multiple branches (Tunis Central, Sfax, Sousse). Data is distributed using **fragmentation** and **replication**.

### Horizontal Fragmentation

Split the `accounts` table by branch:

| Fragment | Predicate | Location |
|----------|-----------|----------|
| accounts_tunis | branch_id = 'TUN' | Tunis Server |
| accounts_sfax | branch_id = 'SFX' | Sfax Server |
| accounts_sousse | branch_id = 'SOU' | Sousse Server |

```sql
-- Tunis fragment
CREATE VIEW accounts_tunis AS
  SELECT * FROM accounts WHERE branch_id = 'TUN';

-- Sfax fragment
CREATE VIEW accounts_sfax AS
  SELECT * FROM accounts WHERE branch_id = 'SFX';
```

### Replication Strategy

| Table | Replication Type | Reasoning |
|-------|-----------------|-----------|
| `branches` | Full replication | Small, read-heavy, rarely changes |
| `exchange_rates` | Full replication | Needed at all branches |
| `accounts` | Horizontal fragmentation | Large table, branch-local data |
| `transactions` | Partial replication (last 90 days) | Audit trail, performance balance |

### Advantages of This Design

1. **Reduced Latency**: Branch queries local data—no cross-network roundtrip for routine operations
2. **Fault Isolation**: A Sfax server failure doesn't affect Tunis or Sousse operations
3. **Scalability**: Each branch can scale independently
4. **Data Sovereignty**: Customer data stays in its regional server (compliance)

### Consistency Model

- **Local transactions**: ACID-compliant using S2PL
- **Distributed transactions**: Two-Phase Commit (2PC) protocol for cross-branch transfers
- **Replica synchronization**: Asynchronous replication with conflict resolution via timestamp ordering
