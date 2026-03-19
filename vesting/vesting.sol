// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../com/IERC20.sol";
import "../com/SafeERC20.sol";
import "../com/Ownable.sol";
import "../com/ReentrancyGuard.sol";

/**
 * @title ESGIN Vesting
 * @dev Predefined distribution plan for ESGIN tokens.
 */
contract Vesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    uint256 public immutable startTimestamp;
    uint256 public constant MONTH = 30 days; 

    struct Schedule {
        address beneficiary;
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 cliffMonths;
        uint256 totalMonths;
        uint256 monthlyAmount;
    }

    mapping(string => Schedule) public schedules;
    string[] public roles = ["reward", "bank", "team", "liquidity", "investment"];

    event TokensReleased(string role, address indexed beneficiary, uint256 amount);

    constructor(address _token, address _initialOwner) Ownable(_initialOwner) {
        require(_token != address(0), "Vesting: token is zero");
        token = IERC20(_token);
        startTimestamp = block.timestamp;

        // 1. Reward Pool: 450M, 60 months linear (M1~)
        schedules["reward"] = Schedule({
            beneficiary: 0x453C16F155DaBF8756e7f86958d35D47774BC724,
            totalAmount: 450_000_000 * 10**18,
            releasedAmount: 0,
            cliffMonths: 1,
            totalMonths: 60,
            monthlyAmount: 7_500_000 * 10**18
        });

        // 2. ESG Bank Pool: 150M, 60 months linear (M1~)
        schedules["bank"] = Schedule({
            beneficiary: 0x3602F2D84860A054240D7DB14a1210Df508324dE,
            totalAmount: 150_000_000 * 10**18,
            releasedAmount: 0,
            cliffMonths: 1,
            totalMonths: 60,
            monthlyAmount: 2_500_000 * 10**18
        });

        // 3. Team: 150M, initial 50M + 12m cliff + 24m linear (M12~M35)
        schedules["team"] = Schedule({
            beneficiary: 0xABbcB65e9201369c905B211102f2f183693CBc03,
            totalAmount: 150_000_000 * 10**18,
            releasedAmount: 0,
            cliffMonths: 12,
            totalMonths: 24,
            monthlyAmount: 4_166_666_67 * 10**16
        });

        // 4. Liquidity: 150M, M1 100M + M12~23 50M
        schedules["liquidity"] = Schedule({
            beneficiary: 0xB833bF8a7F04782d6d83FDDFBe87DFec654f86b8,
            totalAmount: 150_000_000 * 10**18,
            releasedAmount: 0,
            cliffMonths: 12,
            totalMonths: 12,
            monthlyAmount: 4_166_666_67 * 10**16
        });

        // 5. Investment: 100M, M1 100% unlocked
        schedules["investment"] = Schedule({
            beneficiary: 0x2CE059189286267922b33183B8Fa983E131Da842,
            totalAmount: 100_000_000 * 10**18,
            releasedAmount: 0,
            cliffMonths: 1,
            totalMonths: 0,
            monthlyAmount: 0
        });
    }

    /**
     * @dev Manually send initial allocations. Call this once after the contract is funded with tokens.
     */
    function releaseInitial() external onlyOwner nonReentrant {
        // Liquidity initial 100M
        Schedule storage liq = schedules["liquidity"];
        if (liq.releasedAmount == 0) {
            uint256 amount = 100_000_000 * 10**18;
            liq.releasedAmount += amount;
            token.safeTransfer(liq.beneficiary, amount);
            emit TokensReleased("liquidity_initial", liq.beneficiary, amount);
        }

        // Team initial 50M
        Schedule storage team = schedules["team"];
        if (team.releasedAmount == 0) {
            uint256 amount = 50_000_000 * 10**18;
            team.releasedAmount += amount;
            token.safeTransfer(team.beneficiary, amount);
            emit TokensReleased("team_initial", team.beneficiary, amount);
        }

        // Investment 100%
        Schedule storage inv = schedules["investment"];
        if (inv.releasedAmount == 0) {
            inv.releasedAmount += inv.totalAmount;
            token.safeTransfer(inv.beneficiary, inv.totalAmount);
            emit TokensReleased("investment_initial", inv.beneficiary, inv.totalAmount);
        }
    }

    function releaseAll() external onlyOwner nonReentrant {
        for (uint i = 0; i < roles.length; i++) {
            _release(roles[i]);
        }
    }

    function _release(string memory role) internal {
        Schedule storage s = schedules[role];
        uint256 vested = _calculateVested(s, role);
        uint256 releasable = vested - s.releasedAmount;

        if (releasable > 0) {
            s.releasedAmount += releasable;
            token.safeTransfer(s.beneficiary, releasable);
            emit TokensReleased(role, s.beneficiary, releasable);
        }
    }

    /**
     * @dev First linear payment occurs in the month when cliff ends (on day 30 of that month).
     */
    function _calculateVested(Schedule storage s, string memory role) internal view returns (uint256) {
        // Before cliff ends, return only already-released amount (e.g. initial allocation)
        if (block.timestamp < startTimestamp + (s.cliffMonths * MONTH)) {
            return s.releasedAmount;
        }

        uint256 monthsPassed = (block.timestamp - startTimestamp) / MONTH;
        
        // When monthsPassed equals cliffMonths, activeMonths becomes 1 (first payment occurs)
        uint256 activeMonths = monthsPassed - s.cliffMonths + 1;

        if (activeMonths >= s.totalMonths) {
            return s.totalAmount;
        }

        uint256 baseAmount = 0;
        bytes32 roleHash = keccak256(bytes(role));
        if (roleHash == keccak256(bytes("liquidity"))) {
            baseAmount = 100_000_000 * 10**18;
        } else if (roleHash == keccak256(bytes("team"))) {
            baseAmount = 50_000_000 * 10**18;
        }
        
        uint256 linearAmount = baseAmount + (activeMonths * s.monthlyAmount);
        return linearAmount > s.totalAmount ? s.totalAmount : linearAmount;
    }

    function totalVestedAmount() external view returns (uint256) {
        uint256 sum = 0;
        for (uint i = 0; i < roles.length; i++) {
            sum += _calculateVested(schedules[roles[i]], roles[i]);
        }
        return sum;
    }

    function totalReleasedAmount() external view returns (uint256) {
        uint256 sum = 0;
        for (uint i = 0; i < roles.length; i++) {
            sum += schedules[roles[i]].releasedAmount;
        }
        return sum;
    }
}
