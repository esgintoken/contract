# ESGIN Smart Contracts

Solidity smart contracts for the ESGIN token and vesting distribution.

## Overview

- **ESGIN**: ERC20 token (initial supply 1 billion, with lock-up functionality)
- **Vesting**: Contract that distributes foundation tokens to 5 wallets according to a predefined schedule

## Project Structure

```
contract/
├── com/           # Common interfaces and utilities
├── token/         # ESGIN ERC20 token
└── vesting/       # Vesting distribution contract
```

### com/ - Common Contracts

Shared interfaces and base contracts.

| File | Description |
|------|-------------|
| `IERC20.sol` | ERC20 standard interface |
| `IERC1363.sol` | ERC1363 (Payable Token) interface |
| `IERC165.sol` | ERC165 interface |
| `Context.sol` | msg.sender context |
| `Ownable.sol` | Ownership management |
| `ReentrancyGuard.sol` | Reentrancy attack protection |
| `SafeERC20.sol` | ERC20 safe transfer wrapper |
| `Address.sol` | Address utilities |
| `Errors.sol` | Custom error definitions |

### token/ - ESGIN Token

| File | Description |
|------|-------------|
| `ESGIN.sol` | ERC20 token, initial supply 1 billion, lock-up functionality |

**Key Features**
- Standard ERC20 (transfer, approve, transferFrom)
- `transferWithLock` / `transferWithLockEasy`: Callable only by Owner or Approved addresses; locks recipient balance
- `claim()`: Auto-unlock expired locks
- `addApproved` / `removeApproved`: Grant/revoke lock-up permission
- Max 4 years (1460 days) lock duration, max 100 locks per address

### vesting/ - Vesting Contract

| File | Description |
|------|-------------|
| `vesting.sol` | Linear vesting distribution to 5 wallets |

**Distribution Schedule (Total 1B)**

| Role | Share | Total | Schedule |
|------|-------|-------|----------|
| reward | 45% | 450M | M2~ 60 months linear |
| bank | 15% | 150M | M2~ 60 months linear |
| team | 15% | 150M | M1 initial 50M + M13~M36 24 months linear (12m cliff) |
| liquidity | 15% | 150M | M1 initial 100M + M13~M24 50M in 12 installments |
| investment | 10% | 100M | M1 100% unlocked |

**Key Functions**
- `releaseInitial()`: Sends Liquidity 100M, Team 50M, Investment 100M immediately (one-time after deployment)
- `releaseAll()`: Batch transfers currently releasable amount for all roles

## Requirements

- Solidity ^0.8.20

## Deployment Order

1. Deploy **ESGIN** (name, symbol, initialOwner)
2. Deploy **Vesting** (ESGIN address, owner)
3. Owner transfers ESGIN to Vesting contract
4. Owner calls `releaseInitial()`

## License

MIT
