// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.4;

interface IStakingRewardDistribution {
    function rewardAmount() external view returns (uint256);

    function recoverableUnassignedReward()
        external
        view
        returns (uint256);

    function stakedTokensOf(address _staker) external view returns (uint256);

    function getRewardToken() external view returns (address);

    function getClaimedReward(address _claimer)
        external
        view
        returns (uint256);

    function initialize(
        address _rewardTokenAddress,
        address _stakableTokenAddress,
        uint256 _rewardAmount,
        uint64 _startingTimestamp,
        uint64 _endingTimestamp,
        bool _locked,
        uint256 _stakingCap
    ) external;

    function cancel() external;

    function recoverRewardAfterCancel() external;

    function recoverUnassignedReward() external;

    function stake(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function claim(uint256 _amounts, address _recipient) external;

    function exit(address _recipient) external;

    function claimableReward(address _staker)
        external
        view
        returns (uint256);

    function renounceOwnership() external;

    function transferOwnership(address _newOwner) external;

    function addReward(uint256 _amount) external;
}