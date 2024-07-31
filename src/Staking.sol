
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract Staking is Initializable, UUPSUpgradeable, PausableUpgradeable,  OwnableUpgradeable{
      //////////////////////
     /////// Errors ///////
    //////////////////////

    error Staking__NotNFTOwner();
    error Staking__NotApproved();
    error Staking__CannotClaim();
    error Staking__NotUnbonded();
    error Staking__AlreadyUnbonded();
    error Staking__CannotWithdraw();
    error Staking__ZeroAddress();
    error Staking__Unauthorized_Upgrade();


      /////////////////////
     /////// State ///////
    /////////////////////

    IERC721 private s_nft;
    IERC20 private s_rewardToken;
    uint256 private s_rewardAmount;
    uint256 private s_delayPeriod;
    uint256 private s_unbondingPeriod;
    mapping(uint256 tokenId => address staker) private s_nftStaker;
    mapping(address staker => uint256 total) public s_stakersNfts;
    mapping(address staker => uint256 time) private s_lastClaimedTime;
    mapping(address staker => uint256 reward) private s_stakerRewards;
    mapping(address staker => uint256) private s_lastCalculationBlock;
    mapping(uint256 tokenId => bool unbonded) private s_isNFtUnbonded;
    mapping(uint256 tokenId => uint256 time) private s_unbondingTime;


      /////////////////////// 
     /////// Events ////////
    ///////////////////////

    event Staked(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId);
    event Claimed(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 tokenId);

     /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(){
        _disableInitializers();
    }
    
      //////////////////////////// 
     /// Initializer Function ///
    ////////////////////////////

    /**
    // @dev Initializes the contract
    // @param _nft The address of the NFT contract
    // @param _rewardToken The address of the reward token
    // @param _rewardAmount The amount of reward token to distribute per block
    // @param _delayPeriod The delay period before a user can claim rewards
    // @param _unbondingPeriod The period after which a user can withdraw their NFT 
    // after initiating the unbonding process
    */
    function initialize(
        IERC721 _nft,
        IERC20 _rewardToken,
        uint256 _rewardAmount,
        uint256 _delayPeriod,
        uint256 _unbondingPeriod,
        address owner
    ) public initializer {
        __Pausable_init();
        __Ownable_init(owner);
        s_nft = _nft;
        s_rewardToken = _rewardToken;
        s_rewardAmount = _rewardAmount;
        s_delayPeriod = _delayPeriod;
        s_unbondingPeriod = _unbondingPeriod;
    }

      ///////////////////////// 
     /// Staking Functions ///
    /////////////////////////

    /**
    // @dev Stakes an NFT
    // @param tokenId The ID of the NFT to stake
    // Requirements:
    // - The caller must be the owner of the NFT
    // - The contract must be approved to transfer the NFT
    // - The NFT must not be already staked
    */
    function stake(uint256 tokenId) external whenNotPaused {
        if(s_nft.ownerOf(tokenId) != msg.sender) {
            revert Staking__NotNFTOwner();
        }
        if(s_nft.getApproved(tokenId) != address(this)) {
            revert Staking__NotApproved();
        }
        
        s_nft.transferFrom(msg.sender, address(this), tokenId);
        s_nftStaker[tokenId] = msg.sender;
        s_lastClaimedTime[msg.sender] = block.timestamp;
        uint256 lastCalcuatedBlock = s_lastCalculationBlock[msg.sender];
        if(lastCalcuatedBlock !=0){
            s_stakerRewards[msg.sender] += _calculateReward(msg.sender);
        }
        s_stakersNfts[msg.sender]+=1;
        s_lastCalculationBlock[msg.sender] = block.number;
        emit Staked(msg.sender, tokenId);
    }

    /**  
    // @dev Claims rewards
    // Requirements:
    // - The caller must have rewards to claim
    // - The caller must wait for the delay period before claiming rewards again
    */
    function claim() external whenNotPaused{
        if(s_lastClaimedTime[msg.sender] + s_delayPeriod > block.timestamp) {
            revert Staking__CannotClaim();
        }
        uint256 newReward = _calculateReward(msg.sender);
        uint256 totalReward = s_stakerRewards[msg.sender] + newReward;
        if(totalReward == 0) {
            revert Staking__CannotClaim();
        }
        s_stakerRewards[msg.sender] = 0;
        s_lastClaimedTime[msg.sender] = block.timestamp;
        s_lastCalculationBlock[msg.sender] = block.number;
        s_rewardToken.transfer(msg.sender, totalReward);   
        emit Claimed(msg.sender, totalReward); 
    }

    /** 
    // @dev Unstakes an NFT
    // @param tokenId The ID of the NFT to unstake
    // Requirements:
    // - The caller must be the owner of the NFT
    // - The NFT must not be already unbonded
    // Effects:
    // - The NFT is marked as unbonded
    */
    function unstake(uint256 tokenId) external whenNotPaused {
        if(s_nftStaker[tokenId] != msg.sender) {
            revert Staking__NotNFTOwner();
        }
        if(s_isNFtUnbonded[tokenId]) {
            revert Staking__AlreadyUnbonded();
        }
        s_stakerRewards[msg.sender] += _calculateReward(msg.sender);
        s_isNFtUnbonded[tokenId] = true;
        s_stakersNfts[msg.sender] -= 1;
        s_unbondingTime[tokenId] = block.timestamp;
        emit Unstaked(msg.sender, tokenId);
    }

    /**
    // @dev Withdraws an NFT
    // @param tokenId The ID of the NFT to withdraw
    // Requirements:
    // - The caller must be the owner of the NFT
    // - The NFT must be unbonded
    // - The NFT must have cleared the unbonding period
    // Effects:
    // - The NFT is transferred back to the owner
    */
    function withdraw(uint256 tokenId) external whenNotPaused{
        if(s_nftStaker[tokenId] != msg.sender) {
            revert Staking__NotNFTOwner();
        }
        if(!s_isNFtUnbonded[tokenId]) {
            revert Staking__NotUnbonded();
        }
        if(s_unbondingTime[tokenId] + s_unbondingPeriod > block.timestamp) {
            revert Staking__CannotWithdraw();
        }
        s_nftStaker[tokenId] = address(0);
        s_isNFtUnbonded[tokenId] = false;
        s_nft.safeTransferFrom(address(this), msg.sender, tokenId);
        emit Withdrawn(msg.sender, tokenId);
    }

      //////////////////////////// 
     //// Internal Functions ////
    ////////////////////////////

    /** 
    // @dev Calculates the reward for a user
    // @param user The address of the user
    // @return The reward amount
    */
    function _calculateReward(address user) private view returns (uint256) {
        uint256 lastCalcuatedBlock = s_lastCalculationBlock[user];
        uint256 userNftNumber = s_stakersNfts[user];

        uint256 blocks = block.number - lastCalcuatedBlock;
        uint256 reward = userNftNumber*blocks * s_rewardAmount;
        return reward;
    }

      ///////////////////////// 
     //// Owner Functions ////
    /////////////////////////

    /**
    // @dev Sets the reward amount per block
    // @param _rewardAmount The reward amount
    // Requirements:
    // - The caller must be the owner
    */
    function setRewardAmount(uint256 _rewardAmount) external onlyOwner {
        s_rewardAmount = _rewardAmount;
    }

    /**
    // @dev Sets the unbonding period
    // @param _unbondingPeriod The unbonding period
    // Requirements:
    // - The caller must be the owner
    */
    function setUnbondingPeriod(uint256 _unbondingPeriod) external onlyOwner {
        s_unbondingPeriod = _unbondingPeriod;
    }
    /** 
    // @dev Sets the delay period
    // @param _delayPeriod The delay period
    // Requirements:
    // - The caller must be the owner
    */
    function setDelayPeriod(uint256 _delayPeriod) external onlyOwner {
        s_delayPeriod = _delayPeriod;
    }

    /** 
    // @dev Pauses the contract
    */
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /** 
    // @dev Unpauses the contract
    */
    function unpause() public onlyOwner whenPaused{
        _unpause();
    }

    /** 
    // @dev Returns the rewards of a the caller
    // @return The reward amount
    */
    function getRewards() external view returns (uint256) {
        return getRewardsForAddress(msg.sender);
    }
    /** 
    // @dev Returns the rewards of a user
    // @param user The address of the user
    // @return The reward amount
    */
    function getRewardsForAddress(address user) public view returns (uint256) {
        return s_stakerRewards[user] + _calculateReward(user);
    }

    /**
     * @dev Get the staker of an NFT
     * @param tokenId The ID of the NFT 
     * @return The address of the staker
     */
    function getStaker(uint256 tokenId) external view returns (address) {
        return s_nftStaker[tokenId];
    }

    /**
     * @dev Get the Total NFTs staked by a user
     * @param user The address of the user
     * @return The total number of NFTs staked 
     */
    function getTotalNftsStaked(address user) external view returns (uint256) {
        return s_stakersNfts[user];
    }

    /**
     * @dev Get the Delay Period for claiming rewards
     * @return The delay period 
     */
    function getDelayPeriod() external view returns (uint256) {
        return s_delayPeriod;
    }

    /**
     * @dev Get the Unbonding Period
     * @return The unbonding period 
     */
    function getUnbondingPeriod() external view returns (uint256) {
        return s_unbondingPeriod;
    }

    /**
     * @dev Get the Reward Amount per block
     * @return The reward amount 
     */
    function getRewardAmount() external view returns (uint256) {
        return s_rewardAmount;
    }

    /**
     * @dev get implementation of the contract
     * @return The implementation address
     */
    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    function _authorizeUpgrade(address newImplementation) internal  view override {
        if(newImplementation == address(0)) {
            revert Staking__ZeroAddress();
        }
        if (msg.sender != owner()) {
            revert Staking__Unauthorized_Upgrade();
        }
    }
}