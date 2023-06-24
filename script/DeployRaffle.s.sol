// SPDX-License-Identifier: MIT

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

pragma solidity ^0.8.18;

contract DeployRaffle is Script {
    function run() external returns (Raffle, HelperConfig) {
        // Get the configuation for the active network
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 entranceFee,
            uint256 interval,
            address vrfCoordinator,
            bytes32 gasLane,
            uint64 subscriptionId,
            uint32 callbackGasLimit,
            address link
        ) = helperConfig.activeNetworkConfig();

        // Check that there is a subscriptionId and if not create one
        if (subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            subscriptionId = createSubscription.createSubscription(
                vrfCoordinator
            );
        }

        // Fund subscription using config and subscriptionId we possibly created above
        FundSubscription fundSubscription = new FundSubscription();
        fundSubscription.fundSubscription(vrfCoordinator, subscriptionId, link);

        // Deploy the raffle contract
        vm.startBroadcast();
        Raffle raffle = new Raffle(
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit
        );
        vm.stopBroadcast();

        // Add the raffle contract as a consumer of the subscription
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(raffle),
            vrfCoordinator,
            subscriptionId
        );

        // Return the raffle contract and the helper config
        return (raffle, helperConfig);
    }
}
