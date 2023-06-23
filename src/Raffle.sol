// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample raffle contract
 * @author Jordan Greer
 * @notice This contract is a sample raffle contract
 * @dev Implements Chainlink VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {
    //Errors

    error Raffle__NotEnoughEthSent();
    error Raffle__NotEnoughTimePassed();
    error Raffle_TransferFaild();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(
        uint256 current,
        uint256 numPlayers,
        uint256 raffleState
    );

    // State variables

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    // @dev duration of the lottery in secods
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    uint256 private s_lastTimeStamp;
    address payable[] private s_players;
    address payable private s_recentWinner;
    RaffleState private s_raffleState;

    // Events

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    // Constructor

    constructor(
        uint256 _entranceFee,
        uint256 _interval,
        address _vrfCoordinator,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        i_entranceFee = _entranceFee;
        i_interval = _interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        i_gasLane = _gasLane;
        i_subscriptionId = _subscriptionId;
        i_callbackGasLimit = _callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    // External and public functions.
    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Automation nodes call
     * to see if it's time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. The time interval has passed between raffle runs or the interval
     * 2. The raffle is in open state
     * 3. There are players
     * 4. The contract has ETH
     * 5. (Implicit)The contract has LINK
     */
    function checkUpKeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performsData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool raffleIsOpen = s_raffleState == RaffleState.OPEN;
        bool hasPlayers = s_players.length > 0;
        bool hasEth = address(this).balance > 0;
        upkeepNeeded = timeHasPassed && raffleIsOpen && hasPlayers && hasEth;
        return (upkeepNeeded, bytes("0x0"));
    }

    /**
     * @dev This is the function that the Chainlink Automation nodes call
     * 1. Get a random number from Chainlink VRF
     * 2. Use random number to pick a winner
     * 3. Automatically call the winner
     */

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpKeep(""); // Make sure its time for an upkeep
        if (!upkeepNeeded) {
            revert Raffle__UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING; // Change the raffle state to calculating

        i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subscriptionId, // id funded with link
            REQUEST_CONFIRMATIONS, // block confirmations
            i_callbackGasLimit, // gas limit for calling us back
            NUM_WORDS // number of words or 'random numbers' to return
        );
    }

    // Internal and private functions

    function fulfillRandomWords(
        uint256 /* requestId*/,
        uint256[] memory randomWords
    ) internal override {
        // Index of winner by the random number modulo number of players.
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        // Cast winners index on players array to payable address
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner; // Track the most recent winner
        s_raffleState = RaffleState.OPEN; //Change the raffle back to open

        s_players = new address payable[](0); // Reset the players array
        s_lastTimeStamp = block.timestamp; // Reset the time stamp

        // Emit
        emit PickedWinner(winner);

        // Send the winner the balance of the contract

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFaild();
        }

        emit PickedWinner(winner);
    }

    // Getter functions

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }
}
