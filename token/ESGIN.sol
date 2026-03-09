// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../com/IERC20.sol";
import "../com/Context.sol";
import "../com/Ownable.sol";
import "../com/ReentrancyGuard.sol";

/**
 * @title ESGIN
 * @dev Vesting 컨트랙트와 함께 사용할 표준 ERC20 토큰
 *      초기 공급량(10억)을 owner에게 발행하며, owner가 Vesting 컨트랙트로 전송 후 배분
 * @notice Owner 및 addApproved로 등록된 주소는 신뢰 가정됨. transferWithLock/transferWithLockEasy는 해당 주소만 호출 가능.
 */
contract ESGIN is Context, IERC20, Ownable, ReentrancyGuard {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private constant _decimals = 18;

    // Lock (transferWithLockEasy) state
    uint256 public constant MAX_LOCKS_PER_ADDRESS = 100;
    uint256 public constant MAX_LOCK_DURATION = 1460 days; // 4 years
    struct LockInfo {
        uint256 releaseTime;
        uint256 amount;
    }
    mapping(address => LockInfo[]) public timelockList;
    mapping(address => uint256) public lockedAmount;
    mapping(address => uint256) public lastLockTime;
    uint256 public lockCooldownPeriod;

    // Only approved addresses (or owner) may call transferWithLock / transferWithLockEasy
    mapping(address => bool) public approved;
    address[] private _approvedList;

    modifier onlyApproved() {
        require(owner() == _msgSender() || approved[_msgSender()], "Must call by Owner or Approved");
        _;
    }

    event Lock(address indexed holder, uint256 value, uint256 releaseTime, address indexed operator);
    event Unlock(address indexed holder, uint256 value, address indexed operator);
    event ApprovedAdded(address indexed addr);
    event ApprovedRemoved(address indexed addr);

    /**
     * @dev Vesting 스케줄 총량에 맞춰 초기 공급량 10억(1e9 * 1e18) 발행
     * @param name_ 토큰 이름
     * @param symbol_ 토큰 심볼
     * @param initialOwner_ 초기 소유자 (발행량 수령 주소, 보통 Vesting 배포자)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address initialOwner_
    ) Ownable(initialOwner_) {
        _name = name_;
        _symbol = symbol_;
        _totalSupply = 1_000_000_000 * 10 ** _decimals; // 10억
        _balances[initialOwner_] = _totalSupply;
        emit Transfer(address(0), initialOwner_, _totalSupply);
        lockCooldownPeriod = 1 hours;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) public virtual override returns (bool) {
        address owner = _msgSender();
        if (timelockList[owner].length > 0) _autoUnlock(owner);
        _transfer(owner, to, value);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /// @dev allowance를 안전하게 증가 (approve race 완화)
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /// @dev allowance를 안전하게 감소
    function decreaseAllowance(address spender, uint256 requestedDecrease) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= requestedDecrease, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - requestedDecrease);
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public virtual override returns (bool) {
        if (timelockList[from].length > 0) _autoUnlock(from);
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal virtual {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= value, "ERC20: insufficient balance");
        require(fromBalance - lockedAmount[from] >= value, "ERC20: exceeds unlocked balance");
        unchecked {
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _lock(address holder, uint256 value, uint256 releaseTime) internal {
        require(holder != address(0), "Lock: zero address");
        require(value > 0, "Lock: amount zero");
        require(releaseTime > block.timestamp, "Lock: release time must be future");
        require(releaseTime <= block.timestamp + MAX_LOCK_DURATION, "Lock: exceeds max duration");
        require(_balances[holder] - lockedAmount[holder] >= value, "Lock: insufficient unlocked");
        require(timelockList[holder].length < MAX_LOCKS_PER_ADDRESS, "Lock: too many locks");
        uint256 cooldown = lockCooldownPeriod > 0 ? lockCooldownPeriod : 1 hours;
        if (msg.sender != holder && lastLockTime[holder] + cooldown > block.timestamp) {
            require(lastLockTime[holder] + cooldown <= block.timestamp, "Lock: cooldown");
        }
        lockedAmount[holder] += value;
        timelockList[holder].push(LockInfo(releaseTime, value));
        lastLockTime[holder] = block.timestamp;
        _sortLocksByReleaseTime(holder);
        emit Lock(holder, value, releaseTime, msg.sender);
    }

    function _sortLocksByReleaseTime(address holder) internal {
        LockInfo[] storage locks = timelockList[holder];
        uint256 len = locks.length;
        for (uint256 i = 1; i < len; i++) {
            LockInfo memory key = locks[i];
            uint256 j = i;
            while (j > 0 && locks[j - 1].releaseTime > key.releaseTime) {
                locks[j] = locks[j - 1];
                j--;
            }
            locks[j] = key;
        }
    }

    function _removeLock(address holder, uint256 idx) internal {
        LockInfo storage info = timelockList[holder][idx];
        uint256 amount = info.amount;
        uint256 lastIdx = timelockList[holder].length - 1;
        if (idx != lastIdx) timelockList[holder][idx] = timelockList[holder][lastIdx];
        timelockList[holder].pop();
        require(lockedAmount[holder] >= amount, "Unlock: underflow");
        lockedAmount[holder] -= amount;
        emit Unlock(holder, amount, msg.sender);
    }

    function _autoUnlock(address holder) internal returns (uint256 count) {
        require(holder != address(0), "Unlock: zero address");
        while (timelockList[holder].length > 0 && block.timestamp >= timelockList[holder][0].releaseTime) {
            _removeLock(holder, 0);
            count++;
        }
        return count;
    }

    function _approve(address owner, address spender, uint256 value) internal virtual {
        require(owner != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= value, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - value);
            }
        }
    }

    function addApproved(address _addr) external onlyOwner {
        require(_addr != address(0), "Invalid address");
        require(!approved[_addr], "Already approved");
        approved[_addr] = true;
        _approvedList.push(_addr);
        emit ApprovedAdded(_addr);
    }

    function removeApproved(address _addr) external onlyOwner {
        require(_addr != address(0), "Invalid address");
        approved[_addr] = false;
        for (uint256 i = 0; i < _approvedList.length; i++) {
            if (_approvedList[i] == _addr) {
                _approvedList[i] = _approvedList[_approvedList.length - 1];
                _approvedList.pop();
                break;
            }
        }
        emit ApprovedRemoved(_addr);
    }

    function getApprovedList() external view returns (address[] memory) {
        return _approvedList;
    }

    function isApproved(address _addr) public view returns (bool) {
        if (_addr == address(0)) return false;
        return _addr == owner() || approved[_addr];
    }

    /// @dev Send tokens to holder and lock until releaseTime (only owner or approved)
    function transferWithLock(address holder, uint256 value, uint256 releaseTime) public onlyApproved nonReentrant returns (bool) {
        require(holder != address(0), "transferWithLock: zero address");
        require(value > 0, "transferWithLock: zero amount");
        require(_balances[_msgSender()] - lockedAmount[_msgSender()] >= value, "transferWithLock: insufficient unlocked");
        _transfer(_msgSender(), holder, value);
        _lock(holder, value, releaseTime);
        return true;
    }

    /// @dev Same as transferWithLock but releaseTime = now + lockupDaysParam days (only owner or approved)
    function transferWithLockEasy(address holder, uint256 valueEth, uint256 lockupDaysParam) public onlyApproved returns (bool) {
        require(lockupDaysParam > 0 && lockupDaysParam <= 3650, "transferWithLockEasy: invalid days");
        uint256 valueWei = valueEth * (10**18);
        uint256 releaseTime = block.timestamp + (lockupDaysParam * 1 days);
        return transferWithLock(holder, valueWei, releaseTime);
    }

    /// @dev Unlock all expired locks for msg.sender
    function claim() public returns (uint256) {
        return _autoUnlock(_msgSender());
    }

    function getLockCount(address holder) public view returns (uint256) {
        return timelockList[holder].length;
    }

    function setLockCooldownPeriod(uint256 _period) external onlyOwner {
        lockCooldownPeriod = _period;
    }
}
