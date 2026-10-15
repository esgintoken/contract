# Ownership Renouncement Notice — ESGIN Token

## Summary

We have executed `renounceOwnership()` on the ESGIN token contract. The contract now has no owner (`owner() == address(0)`), and ownership cannot be restored.

## Permanently Disabled Functions

The following functions that were previously restricted to the owner are permanently disabled:

| Function                                  | Previous capability                                          |
| ----------------------------------------- | ------------------------------------------------------------ |
| `addApproved` / `removeApproved`          | Manage the approved address list used for `transferWithLock` |
| `setLockCooldownPeriod`                   | Update the lock cooldown period                              |
| `transferOwnership` / `renounceOwnership` | Transfer or renounce ownership                               |

## Unchanged Behavior

- Standard ERC-20 functions (`transfer`, `approve`, `transferFrom`, etc.) remain fully available.
- User lock / `claim` behavior continues to work normally.
- This contract does not include mint, burn, pause, or balance-seizure functions.

## On-chain References

| Item                 | Value                                                                                      |
| -------------------- | ------------------------------------------------------------------------------------------ |
| Token contract       | 0x9F293778c23DA45Eb7126DD4a8cB3923547e0C3D                                                 |
| Renounce transaction | 0xf040e5cdeaee115e45c14e3cb6577479e620725857735e7b4f1d70f70f8a07b4                         |
| Explorer             | https://etherscan.io/tx/0xf040e5cdeaee115e45c14e3cb6577479e620725857735e7b4f1d70f70f8a07b4 |
| Date                 | 2026-10-12                                                                                 |
