// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IStakingRewardDistribution.sol";
import "./interfaces/IStakingRewardDistributionFactory.sol";

/**
 * Errors codes:
 *
 * SRF01: cannot pause staking (already paused)
 * SRF02: cannot resume staking (already active)
 */
contract StakingRewardDistributionFactory is
    IStakingRewardDistributionFactory,
    Ownable
{
    using SafeERC20 for IERC20;

    address public override implementation;
    bool public override stakingPaused;
    IStakingRewardDistribution[] public override distributions;

    event DistributionCreated(address owner, address deployedAt);

    constructor(address _implementation) {
        implementation = _implementation;
    }

    function upgradeImplementation(address _implementation)
        external
        override
        onlyOwner
    {
        implementation = _implementation;
    }

    function pauseStaking() external override onlyOwner {
        require(!stakingPaused, "SRF01");
        stakingPaused = true;
    }

    function resumeStaking() external override onlyOwner {
        require(stakingPaused, "SRF02");
        stakingPaused = false;
    }

    function createDistribution(
        address _rewardTokenAddress,
        address _stakableTokenAddress,
        uint256 _rewardAmount,
        uint64 _startingTimestamp,
        uint64 _endingTimestamp,
        bool _locked,
        uint256 _stakingCap
    ) public override {
        address _distributionProxy = Clones.clone(implementation);
        IERC20(_rewardTokenAddress).safeTransferFrom(
            msg.sender,
            _distributionProxy,
            _rewardAmount
        );
        IStakingRewardDistribution _distribution =
            IStakingRewardDistribution(_distributionProxy);
        _distribution.initialize(
            _rewardTokenAddress,
            _stakableTokenAddress,
            _rewardAmount,
            _startingTimestamp,
            _endingTimestamp,
            _locked,
            _stakingCap
        );
        _distribution.transferOwnership(msg.sender);
        distributions.push(_distribution);
        emit DistributionCreated(msg.sender, address(_distribution));
    }

    function getDistributionsAmount() external view override returns (uint256) {
        return distributions.length;
    }
}