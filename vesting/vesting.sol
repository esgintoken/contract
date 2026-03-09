// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../com/IERC20.sol";
import "../com/SafeERC20.sol";
import "../com/Ownable.sol";

/**
 * @title FoundationTokenDistributor
 * @dev Contract that distributes foundation tokens to 5 wallets according to a predefined schedule (based on distribution plan)
 */
contract Vesting is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    uint256 public immutable startTimestamp;
    uint256 public constant MONTH =  30 days; //for testing set to 30 minutes

    struct Schedule {
        address beneficiary;    // beneficiary wallet address
        uint256 totalAmount;   // total allocation
        uint256 releasedAmount; // already released amount
        uint256 cliffMonths;   // cliff months
        uint256 totalMonths;   // total number of payments
        uint256 monthlyAmount; // monthly amount (last month pays remaining balance in full)
    }

    mapping(string => Schedule) public schedules;
    string[] public roles = ["reward", "bank", "team", "liquidity", "investment"];

    event TokensReleased(string role, address beneficiary, uint256 amount);

    constructor(address _token, address _initialOwner) Ownable(_initialOwner) {
        token = IERC20(_token);
        startTimestamp = block.timestamp;

        // 1. Reward Pool: 45% 450M, 60 months linear (M2~)
        schedules["reward"] = Schedule({
            beneficiary: 0x453C16F155DaBF8756e7f86958d35D47774BC724,
            totalAmount: 450_000_000 * 10**18,
            releasedAmount: 0,
            cliffMonths: 1,
            totalMonths: 60,
            monthlyAmount: 7_500_000 * 10**18
        });

        // 2. ESG Bank Pool: 15% 150M, 60 months linear (M2~)
        schedules["bank"] = Schedule({
            beneficiary: 0x3602F2D84860A054240D7DB14a1210Df508324dE,
            totalAmount: 150_000_000 * 10**18,
            releasedAmount: 0,
            cliffMonths: 1,
            totalMonths: 60,
            monthlyAmount: 2_500_000 * 10**18
        });

        // 3. Team: 15% 150M, initial 50M(releaseInitial) + 12m cliff + 24 months linear (M13~M36)
        schedules["team"] = Schedule({
            beneficiary: 0xABbcB65e9201369c905B211102f2f183693CBc03,
            totalAmount: 150_000_000 * 10**18,
            releasedAmount: 0,
            cliffMonths: 12,
            totalMonths: 24,
            monthlyAmount: 4_166_666_67 * 10**16 // 100M / 24
        });

        // 4. Liquidity: 15% 150M, M1 initial 100M + M13~24 50M in 12 installments
        schedules["liquidity"] = Schedule({
            beneficiary: 0xB833bF8a7F04782d6d83FDDFBe87DFec654f86b8,
            totalAmount: 150_000_000 * 10**18,
            releasedAmount: 0,
            cliffMonths: 12,
            totalMonths: 12,
            monthlyAmount: 4_166_666_67 * 10**16 // 50M / 12
        });

        // 5. Investment: 10% 100M, M1 100% unlocked
        schedules["investment"] = Schedule({
            beneficiary: 0x2CE059189286267922b33183B8Fa983E131Da842, // replace with actual address
            totalAmount: 100_000_000 * 10**18,
            releasedAmount: 0,
            cliffMonths: 1,
            totalMonths: 0,
            monthlyAmount: 0
        });
    }

    /**
     * @dev Used to manually send initial Liquidity amount (100M), Team initial amount (50M), and Investment initial amount (100M) right after deployment
     */
    function releaseInitial() external onlyOwner {
        Schedule storage s = schedules["liquidity"];
        require(s.releasedAmount == 0, "Liquidity initial already released");
        uint256 liquidityAmount = 100_000_000 * 10**18;
        s.releasedAmount += liquidityAmount;
        token.safeTransfer(s.beneficiary, liquidityAmount);
        emit TokensReleased("liquidity_initial", s.beneficiary, liquidityAmount);

        Schedule storage team = schedules["team"];
        require(team.releasedAmount == 0, "Team initial already released");
        uint256 teamAmount = 50_000_000 * 10**18;
        team.releasedAmount += teamAmount;
        token.safeTransfer(team.beneficiary, teamAmount);
        emit TokensReleased("team_initial", team.beneficiary, teamAmount);

        Schedule storage inv = schedules["investment"];
        require(inv.releasedAmount == 0, "Investment initial already released");
        inv.releasedAmount += inv.totalAmount;
        token.safeTransfer(inv.beneficiary, inv.totalAmount);
        emit TokensReleased("investment_initial", inv.beneficiary, inv.totalAmount);
    }

    /**
     * @dev Calculates and transfers the currently releasable amount for all wallets
     */
    function releaseAll() external onlyOwner {
        for (uint i = 0; i < roles.length; i++) {
            _release(roles[i]);
        }
    }

    function _release(string memory role) internal {
        Schedule storage s = schedules[role];
        uint256 vestionAmount = _calculateVested(s, role);
        uint256 releasable = vestionAmount - s.releasedAmount;

        if (releasable > 0) {
            s.releasedAmount += releasable;
            token.safeTransfer(s.beneficiary, releasable);
            emit TokensReleased(role, s.beneficiary, releasable);
        }
    }

    /**
     * @dev Calculates the total cumulative amount to be released based on current time
     *      Caps at totalAmount on the last month to pay remaining balance in full
     */
    function _calculateVested(Schedule storage s, string memory role) internal view returns (uint256) {
        if (block.timestamp < startTimestamp + (s.cliffMonths * MONTH)) {
            // Before cliff period, return only initial release amount (e.g. Liquidity initial 100M)
            return s.releasedAmount;
        }

        uint256 monthsPassed = (block.timestamp - startTimestamp) / MONTH;
        uint256 activeMonths = monthsPassed - s.cliffMonths;

        if (activeMonths >= s.totalMonths) {
            // Return total amount when period ends -> pay remaining balance in full on last month release
            return s.totalAmount;
        }

        // Liquidity initial 100M and Team initial 50M were released in releaseInitial, so account for that
        uint256 baseAmount = 0;
        if (keccak256(bytes(role)) == keccak256(bytes("liquidity"))) {
            baseAmount = 100_000_000 * 10**18;
        } else if (keccak256(bytes(role)) == keccak256(bytes("team"))) {
            baseAmount = 50_000_000 * 10**18;
        }
        uint256 linearAmount = baseAmount + (activeMonths * s.monthlyAmount);
        // Cap to prevent exceeding totalAmount and ensure remaining balance paid in full on last month
        return linearAmount > s.totalAmount ? s.totalAmount : linearAmount;
    }

    /**
     * @dev Returns the sum of total vested amount for all roles up to the current time
     */
    function totalVestedAmount() external view returns (uint256) {
        uint256 sum = 0;
        for (uint i = 0; i < roles.length; i++) {
            Schedule storage s = schedules[roles[i]];
            sum += _calculateVested(s, roles[i]);
        }
        return sum;
    }

    /**
     * @dev Returns the sum of total released amount for all roles up to the current time
     */
    function totalReleasedAmount() external view returns (uint256) {
        uint256 sum = 0;
        for (uint i = 0; i < roles.length; i++) {
            Schedule storage s = schedules[roles[i]];
            sum += s.releasedAmount;
        }
        return sum;
    }
}