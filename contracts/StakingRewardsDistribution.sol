// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IStakingRewardDistributionFactory.sol";
import "./interfaces/IStakingRewardDistribution.sol";

/**
 * Errors codes:
 *
 * SRD01: invalid starting timestamp
 * SRD02: invalid time duration
 * SRD03: inconsistent reward token/amount
 * SRD04: 0 address as reward token
 * SRD05: no reward
 * SRD06: no funding
 * SRD07: 0 address as stakable token
 * SRD08: distribution already started
 * SRD09: tried to stake nothing
 * SRD10: staking cap hit
 * SRD11: tried to withdraw nothing
 * SRD12: funds locked until the distribution ends
 * SRD13: withdrawn amount greater than current stake
 * SRD14: inconsistent claimed amounts
 * SRD15: insufficient claimable amount
 * SRD16: 0 address owner
 * SRD17: caller not owner
 * SRD18: already initialized
 * SRD19: invalid state for cancel to be called
 * SRD20: not started
 * SRD21: already ended
 * SRD23: no rewards are claimable while claiming all
 * SRD24: no rewards are claimable while manually claiming an arbitrary amount of rewards
 * SRD25: staking is currently paused
 * SRD26: no rewards were added
 * SRD27: maximum number of reward tokens breached
 * SRD28: duplicated reward tokens
 * SRD29: distribution must be canceled
 */
contract StakingRewardDistribution is IStakingRewardDistribution {
    using SafeERC20 for IERC20;

    uint224 constant MULTIPLIER = 2**112;

    struct Reward {
        address token;
        uint256 amount;
        uint256 toBeRewarded;
        uint256 perStakedToken;
        uint256 recoverableAmount;
        uint256 claimed;
    }

    struct StakerRewardInfo {
        uint256 consolidatedPerStakedToken;
        uint256 earned;
        uint256 claimed;
    }

    struct Staker {
        uint256 stake;
        StakerRewardInfo rewardInfo;
    }

    Reward public reward;
    mapping(address => Staker) public stakers;
    uint64 public startingTimestamp;
    uint64 public endingTimestamp;
    uint64 public lastConsolidationTimestamp;
    IERC20 public stakableToken;
    address public owner;
    address public factory;
    bool public locked;
    bool public canceled;
    bool public initialized;
    uint256 public totalStakedTokensAmount;
    uint256 public stakingCap;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event Initialized(
        address rewardsTokenAddress,
        address stakableTokenAddress,
        uint256 rewardsAmount,
        uint64 startingTimestamp,
        uint64 endingTimestamp,
        bool locked,
        uint256 stakingCap
    );
    event Canceled();
    event Staked(address indexed staker, uint256 amount);
    event Withdrawn(address indexed withdrawer, uint256 amount);
    event Claimed(address indexed claimer, uint256 amount);
    event Recovered(uint256 amount);
    event RecoveredAfterCancel(address token, uint256 amount);
    event UpdatedReward(uint256 amount);

    function initialize(
        address _rewardTokenAddress,
        address _stakableTokenAddress,
        uint256 _rewardAmount,
        uint64 _startingTimestamp,
        uint64 _endingTimestamp,
        bool _locked,
        uint256 _stakingCap
    ) external override onlyUninitialized {
        require(_startingTimestamp > block.timestamp, "SRD01");
        require(_endingTimestamp > _startingTimestamp, "SRD02");

        // Initializing reward tokens and amounts
        require(_rewardTokenAddress != address(0), "SRD04");
        require(_rewardAmount > 0, "SRD05");
        IERC20 _rewardToken = IERC20(_rewardTokenAddress);
        require(
            _rewardToken.balanceOf(address(this)) >= _rewardAmount,
            "SRD06"
        );
        reward = Reward({
                token: _rewardTokenAddress,
                amount: _rewardAmount,
                toBeRewarded: _rewardAmount * MULTIPLIER,
                perStakedToken: 0,
                recoverableAmount: 0,
                claimed: 0
            });
        

        require(_stakableTokenAddress != address(0), "SRD07");
        stakableToken = IERC20(_stakableTokenAddress);

        owner = msg.sender;
        factory = msg.sender;
        startingTimestamp = _startingTimestamp;
        endingTimestamp = _endingTimestamp;
        lastConsolidationTimestamp = _startingTimestamp;
        locked = _locked;
        stakingCap = _stakingCap;
        initialized = true;
        canceled = false;

        emit Initialized(
            _rewardTokenAddress,
            _stakableTokenAddress,
            _rewardAmount,
            _startingTimestamp,
            _endingTimestamp,
            _locked,
            _stakingCap
        );
    }

    function cancel() external override onlyOwner {
        require(initialized && !canceled, "SRD19");
        require(block.timestamp < startingTimestamp, "SRD08");
        canceled = true;
        emit Canceled();
    }

    function recoverRewardAfterCancel() external override onlyOwner {
        require(canceled, "SRD29");
        IERC20(reward.token).safeTransfer(
            owner,
            IERC20(reward.token).balanceOf(address(this))
        );
    }

    function recoverUnassignedReward()
        external
        override
        onlyOwner
        onlyStarted
    {
        consolidateReward();

        // recoreward rewards a_amounting to be recovered in this tx (if it does not revert),
        // so we add them to the claimed rewards right now
        reward.claimed = reward.recoverableAmount / MULTIPLIER;
        delete reward.recoverableAmount;
        uint256 _recoverableRewards =
            IERC20(reward.token).balanceOf(address(this)) -
                (reward.amount - reward.claimed);
        if (_recoverableRewards > 0) {
            IERC20(reward.token).safeTransfer(owner, _recoverableRewards);
        }
        emit Recovered(_recoverableRewards);
    }

    function stake(uint256 _amount) external override onlyRunning {
        require(
            !IStakingRewardDistributionFactory(factory).stakingPaused(),
            "SRD25"
        );
        require(_amount > 0, "SRD09");
        if (stakingCap > 0) {
            require(totalStakedTokensAmount + _amount <= stakingCap, "SRD10");
        }
        consolidateReward();
        Staker storage _staker = stakers[msg.sender];
        _staker.stake += _amount;
        totalStakedTokensAmount += _amount;
        stakableToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public override onlyStarted {
        require(_amount > 0, "SRD11");
        if (locked) {
            require(block.timestamp > endingTimestamp, "SRD12");
        }
        consolidateReward();
        Staker storage _staker = stakers[msg.sender];
        require(_staker.stake >= _amount, "SRD13");
        _staker.stake -= _amount;
        totalStakedTokensAmount -= _amount;
        stakableToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function claim(uint256 _amount, address _recipient)
        public
        override
        onlyStarted
    {
        consolidateReward();
        Staker storage _staker = stakers[msg.sender];
    
        StakerRewardInfo storage _stakerRewardInfo =
            _staker.rewardInfo;
        uint256 _claimableReward =
            _stakerRewardInfo.earned - _stakerRewardInfo.claimed;
        require(_claimableReward >= _amount, "SRD15");
        if (_amount > 0) {
            _stakerRewardInfo.claimed += _amount;
            reward.claimed += _amount;
            IERC20(reward.token).safeTransfer(_recipient, _amount);
        }
        
        emit Claimed(msg.sender, _amount);
    }

    function exit(address _recipient) external override {
        Staker storage _staker = stakers[msg.sender];
    
        StakerRewardInfo storage _stakerRewardInfo =
            _staker.rewardInfo;
        uint256 _claimableReward = _stakerRewardInfo.earned - _stakerRewardInfo.claimed;
        claim(_claimableReward, _recipient);
        withdraw(stakers[msg.sender].stake);
    }

    function addReward(uint256 _amount)
        external
        override
        onlyStarted
    {
        consolidateReward();
  
        reward.amount += _amount;
        reward.toBeRewarded += _amount * MULTIPLIER;
    
        IERC20(reward.token).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        emit UpdatedReward(_amount);
    }

    function consolidateReward() private {
        uint64 _consolidationTimestamp =
            uint64(Math.min(block.timestamp, endingTimestamp));
        uint256 _lastPeriodDuration =
            uint256(_consolidationTimestamp - lastConsolidationTimestamp);
        uint256 _durationLeft =
            uint256(endingTimestamp - lastConsolidationTimestamp);
        Staker storage _staker = stakers[msg.sender];
        
        StakerRewardInfo storage _stakerRewardInfo =
            _staker.rewardInfo;
        if (_lastPeriodDuration > 0) {
            uint256 _periodReward =
                (_lastPeriodDuration * reward.toBeRewarded) /
                    _durationLeft;
            if (totalStakedTokensAmount == 0) {
                reward.recoverableAmount += _periodReward;
                // no need to update th_amountard per staked token since in this period
                // there have been no staked tokens, so no reward has been given out to stakers
            } else {
                reward.perStakedToken +=
                    _periodReward /
                    totalStakedTokensAmount;
            }
            reward.toBeRewarded -= _periodReward;
        }
        uint256 _rewardSinceLastConsolidation =
            (_staker.stake *
                (reward.perStakedToken -
                    _stakerRewardInfo.consolidatedPerStakedToken)) /
                MULTIPLIER;
        _stakerRewardInfo.earned += _rewardSinceLastConsolidation;
        _stakerRewardInfo.consolidatedPerStakedToken = reward
            .perStakedToken;
        lastConsolidationTimestamp = _consolidationTimestamp;
    }

    function claimableReward(address _account)
        external
        view
        override
        returns (uint256)
    {
        if (!initialized || block.timestamp < startingTimestamp)
            return 0;
        Staker storage _staker = stakers[_account];
        uint64 _consolidationTimestamp =
            uint64(Math.min(block.timestamp, endingTimestamp));
        uint256 _lastPeriodDuration =
            uint256(_consolidationTimestamp - lastConsolidationTimestamp);
        uint256 _durationLeft =
            uint256(endingTimestamp - lastConsolidationTimestamp);

        StakerRewardInfo storage _stakerRewardInfo =
            _staker.rewardInfo;
        uint256 _localRewardPerStakedToken = reward.perStakedToken;
        if (_lastPeriodDuration > 0 && totalStakedTokensAmount > 0) {
            _localRewardPerStakedToken +=
                (_lastPeriodDuration * reward.toBeRewarded) /
                totalStakedTokensAmount /
                _durationLeft;
        }
        uint256 _rewardSinceLastConsolidation =
            (_staker.stake *
                (_localRewardPerStakedToken -
                    _stakerRewardInfo.consolidatedPerStakedToken)) /
                MULTIPLIER;
        uint256 _outstandingReward =
            _rewardSinceLastConsolidation +
            (_stakerRewardInfo.earned - _stakerRewardInfo.claimed);
    
        return _outstandingReward;
    }

    function getRewardToken()
        external
        view
        override
        returns (address)
    {
        return reward.token;
    }

    function rewardAmount()
        external
        view
        override
        returns (uint256)
    {
        return reward.amount;
    }

    function stakedTokensOf(address _staker)
        external
        view
        override
        returns (uint256)
    {
        return stakers[_staker].stake;
    }

    function earnedRewardOf(address _staker)
        external
        view
        returns (uint256)
    {
        Staker storage _stakerFromStorage = stakers[_staker];
        return _stakerFromStorage.rewardInfo.earned;
    }

    function recoverableUnassignedReward()
        external
        view
        override
        returns (uint256)
    {
        uint256 _nonRequiredFunds =
            reward.claimed + (reward.recoverableAmount / MULTIPLIER);
        return IERC20(reward.token).balanceOf(address(this)) -
            (reward.amount - _nonRequiredFunds);
    }

    function getClaimedReward(address _claimer)
        external
        view
        override
        returns (uint256)
    {
        Staker storage _staker = stakers[_claimer];
        return _staker.rewardInfo.claimed;
    }

    function renounceOwnership() external override onlyOwner {
        owner = address(0);
        emit OwnershipTransferred(owner, address(0));
    }

    function transferOwnership(address _newOwner) external override onlyOwner {
        require(_newOwner != address(0), "SRD16");
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "SRD17");
        _;
    }

    modifier onlyUninitialized() {
        require(!initialized, "SRD18");
        _;
    }

    modifier onlyStarted() {
        require(
            initialized && !canceled && block.timestamp >= startingTimestamp,
            "SRD20"
        );
        _;
    }

    modifier onlyRunning() {
        require(
            initialized &&
                !canceled &&
                block.timestamp >= startingTimestamp &&
                block.timestamp <= endingTimestamp,
            "SRD21"
        );
        _;
    }
}