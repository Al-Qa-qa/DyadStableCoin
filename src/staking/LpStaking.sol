// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IUniswapV3PositionsNFT is IERC721 {
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}

interface IXPContract {
    function getXP(address user) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract UniswapV3StakingWithTimeWeightedXPBoost is Ownable {
    IUniswapV3PositionsNFT public uniswapNFT;
    IERC20 public rewardToken;
    IDyadXP public xpContract;  // Reference to the DyadXP contract
    uint256 public rewardRate;  // Tokens rewarded per second per NFT staked
    uint256 public decayRate = 1e18; // Decay rate factor for older XP

    struct StakeInfo {
        uint256 stakedAt;
        uint256 tokenId;
        address owner;
    }

    mapping(uint256 => StakeInfo) public stakes;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public lastUpdateTime;

    constructor(address _uniswapNFT, address _rewardToken, address _xpContract, uint256 _rewardRate) {
        uniswapNFT = IUniswapV3PositionsNFT(_uniswapNFT);
        rewardToken = IERC20(_rewardToken);
        xpContract = IDyadXP(_xpContract);
        rewardRate = _rewardRate;
    }

    function stake(uint256 tokenId) external {
        require(uniswapNFT.ownerOf(tokenId) == msg.sender, "Not the NFT owner");
        uniswapNFT.transferFrom(msg.sender, address(this), tokenId);

        updateReward(msg.sender);

        stakes[tokenId] = StakeInfo({
            stakedAt: block.timestamp,
            tokenId: tokenId,
            owner: msg.sender
        });

        lastUpdateTime[msg.sender] = block.timestamp;
    }

    function unstake(uint256 tokenId) external {
        require(stakes[tokenId].owner == msg.sender, "Not the staker");

        updateReward(msg.sender);

        uniswapNFT.transferFrom(address(this), msg.sender, tokenId);
        delete stakes[tokenId];
    }

    function claimReward() external {
        updateReward(msg.sender);

        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to claim");

        rewards[msg.sender] = 0;
        rewardToken.transfer(msg.sender, reward);
    }

    function updateReward(address account) internal {
        if (lastUpdateTime[account] == 0) {
            lastUpdateTime[account] = block.timestamp;
            return;
        }

        uint256 timeDiff = block.timestamp - lastUpdateTime[account];
        uint256 baseReward = timeDiff * rewardRate;

        // Fetch XP from DyadXP contract
        uint256 xp = xpContract.balanceOf(account);
        uint256 totalXP = xpContract.totalSupply();

        // Calculate time since last XP action to apply a time-weighted decay
        uint256 timeSinceLastAction = block.timestamp - xpContract.lastAction(account);

        // Apply an exponential decay to older XP based on timeSinceLastAction
        uint256 weightedXP = xp * expDecay(timeSinceLastAction);

        // Boost the reward based on weighted XP relative to the total supply of XP
        uint256 boostedReward = baseReward * (1 + (weightedXP * 1e18 / totalXP));

        rewards[account] += boostedReward;
        lastUpdateTime[account] = block.timestamp;
    }

    // Exponential decay function to make recently accrued XP more valuable
    function expDecay(uint256 timeSinceLastAction) internal view returns (uint256) {
        // Example decay formula: decayRate^time
        // Where decayRate < 1, e.g. decayRate = 0.99^seconds since last action
        // The longer the timeSinceLastAction, the smaller the decay factor.
        return decayRate ** timeSinceLastAction / 1e18;
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        rewardRate = _rewardRate;
    }

    function setDecayRate(uint256 _decayRate) external onlyOwner {
        require(_decayRate <= 1e18, "Decay rate should be <= 1");
        decayRate = _decayRate;
    }

    function setXPContract(address _xpContract) external onlyOwner {
        xpContract = IDyadXP(_xpContract);
    }
}