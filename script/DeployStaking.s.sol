// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {Staking} from  "../src/Staking.sol";
import {NFT} from  "../src/NFT.sol";
import {RewardToken} from  "../src/RewardToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployStaking is Script{
    address OWNER = makeAddr("OWNER");

    function run() external returns (address, address, address) {

        vm.startBroadcast();
        // Deploy the NFT contract
        NFT nftContract = new NFT();
        

        // Deploy the reward token contract
        RewardToken rewardToken = new RewardToken();

        // Deploy the staking contract 
        Staking staking = new Staking();
        bytes memory initializationData = abi.encodeWithSelector(
            staking.initialize.selector,
            address(nftContract),
            address(rewardToken),
            5000,
            1*60*60,
            30*60,
            OWNER
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(staking), initializationData);
        rewardToken.transfer(address(proxy), 10**10 * 10 ** 18);
        vm.stopBroadcast();
        return (address(nftContract), address(rewardToken), address(proxy));

    }
}