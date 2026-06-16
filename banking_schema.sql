-- ============================================================
-- Mini Banking System - Schema & Transaction Examples
-- ============================================================

-- Branches table (fully replicated)
CREATE TABLE branches (
  branch_id   CHAR(3)      PRIMARY KEY,
  branch_name VARCHAR(100) NOT NULL,
  city        VARCHAR(50)  NOT NULL,
  server_ip   VARCHAR(15)
);

INSERT INTO branches VALUES
  ('TUN', 'Tunis Central Branch', 'Tunis', '192.168.1.10'),
  ('SFX', 'Sfax Branch', 'Sfax', '192.168.1.20'),
  ('SOU', 'Sousse Branch', 'Sousse', '192.168.1.30');

-- Accounts table (horizontally fragmented by branch)
CREATE TABLE accounts (
  account_id  SERIAL       PRIMARY KEY,
  owner_name  VARCHAR(100) NOT NULL,
  branch_id   CHAR(3)      REFERENCES branches(branch_id),
  balance     DECIMAL(15,2) NOT NULL DEFAULT 0.00 CHECK (balance >= 0),
  account_type CHAR(1)     NOT NULL CHECK (account_type IN ('S','C')), -- Savings/Current
  created_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- Transactions table
CREATE TABLE transactions (
  tx_id        SERIAL       PRIMARY KEY,
  tx_type      VARCHAR(20)  NOT NULL, -- 'TRANSFER', 'DEPOSIT', 'WITHDRAW'
  from_account INT          REFERENCES accounts(account_id),
  to_account   INT          REFERENCES accounts(account_id),
  amount       DECIMAL(15,2) NOT NULL CHECK (amount > 0),
  status       VARCHAR(10)  DEFAULT 'PENDING', -- PENDING, COMMITTED, ABORTED
  initiated_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMP
);

-- ============================================================
-- Safe Transfer Function with Locking (PostgreSQL)
-- ============================================================
CREATE OR REPLACE FUNCTION safe_transfer(
  p_from_id INT,
  p_to_id   INT,
  p_amount  DECIMAL
) RETURNS VARCHAR AS $$
DECLARE
  v_from_balance DECIMAL;
  v_tx_id        INT;
BEGIN
  -- Lock in consistent order to prevent deadlock
  IF p_from_id < p_to_id THEN
    SELECT balance INTO v_from_balance FROM accounts WHERE account_id = p_from_id FOR UPDATE;
    PERFORM account_id FROM accounts WHERE account_id = p_to_id FOR UPDATE;
  ELSE
    PERFORM account_id FROM accounts WHERE account_id = p_to_id FOR UPDATE;
    SELECT balance INTO v_from_balance FROM accounts WHERE account_id = p_from_id FOR UPDATE;
  END IF;

  IF v_from_balance < p_amount THEN
    RETURN 'ERROR: Insufficient funds';
  END IF;

  UPDATE accounts SET balance = balance - p_amount WHERE account_id = p_from_id;
  UPDATE accounts SET balance = balance + p_amount WHERE account_id = p_to_id;

  INSERT INTO transactions (tx_type, from_account, to_account, amount, status, completed_at)
  VALUES ('TRANSFER', p_from_id, p_to_id, p_amount, 'COMMITTED', CURRENT_TIMESTAMP)
  RETURNING tx_id INTO v_tx_id;

  RETURN 'SUCCESS: Transaction ' || v_tx_id;
EXCEPTION
  WHEN OTHERS THEN
    RETURN 'ERROR: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Sample Data
-- ============================================================
INSERT INTO accounts (owner_name, branch_id, balance, account_type) VALUES
  ('Alice Bensalem', 'TUN', 5000.00, 'S'),
  ('Bob Trabelsi', 'TUN', 3200.00, 'C'),
  ('Chloe Mansour', 'SFX', 8750.00, 'S'),
  ('David Khalil', 'SOU', 1200.00, 'C');

-- Test safe transfer
SELECT safe_transfer(1, 2, 500.00);   -- Alice -> Bob: should succeed
SELECT safe_transfer(4, 1, 2000.00);  -- David -> Alice: should fail (insufficient)

-- ============================================================
-- View current balances
-- ============================================================
SELECT a.account_id, a.owner_name, b.branch_name, a.balance, a.account_type
FROM accounts a JOIN branches b ON a.branch_id = b.branch_id
ORDER BY a.account_id;

-- View transaction log
SELECT * FROM transactions ORDER BY initiated_at DESC;
