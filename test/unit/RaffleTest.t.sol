// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();

        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link
        ) = helperConfig.activeNetworkConfig();

        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER);
        //Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        raffle.enterRaffle{value: entranceFee}();
        //Assert
        assert(address(raffle.getPlayer(0)) == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        //Arrange
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    // This test was created around the 5:14:00 mark of the video
    function testCantEnterWhenRaffleIsInCalculation() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    // -----------Check Upkeep Tests----------------

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
        // Assert

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange and Act
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsTrueWhenParametersAreGood() public {
        // Arrange and Act
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Assert
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    ////////////////////////
    //performUpkeep Tests//
    ///////////////////////

    function testPerformUpkeepCanOnlyRunIfTrue() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act and Assert

        raffle.performUpkeep(""); // in forge if .performUpkeep() reverts, test fails
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange

        uint256 current = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpKeepNotNeeded.selector,
                current,
                numPlayers,
                raffleState
            )
        );

        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        // Arrange for player enter raffle and time pass for upkeep
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    // Lets make a test that gets emited info from our Raffle contract
    function testPerfromUpkeepUpdatesRaffleStateAndEmitsReuestId()
        public
        raffleEnteredAndTimePassed //ARRANGE here with modifier
    {
        //ACT
        vm.recordLogs(); // Start the recording of logs emited in this function
        raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); //Vm is special type here
        bytes32 requestId = entries[1].topics[1]; //get the specific emit and content
        //FYI topic 0 is name of entry. 1 is the fist index.

        Raffle.RaffleState rState = raffle.getRaffleState(); //Get the raffle state

        //ASSERT
        assert(uint256(requestId) > 0); // Checking if the indexed topic is not 0
        assert(rState == Raffle.RaffleState.CALCULATING); // Is raffle in calculation
    }

    //////////////////////
    //fulfillRandomWords//
    //////////////////////

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId // This will fuzz with random numbers
    ) public raffleEnteredAndTimePassed {
        //Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId, // fuzzed here to fuzz the requestId
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
    {
        //ARRANGE
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;

        // Loop through to have 5 players enter raffle.
        //FYI "address((uint160(i)))" to get player 1, 2 , 3 etc as address
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1); // +1 for the first player

        vm.recordLogs(); // Start the recording of logs emited in this function
        raffle.performUpkeep(""); // emits requestId
        //Assigns logs to entries variable. This read will consume logs.
        Vm.Log[] memory entries = vm.getRecordedLogs(); //Vm is special type here
        bytes32 requestId = entries[1].topics[1]; //get the specific emit and content

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //Reassigning entries variable after logs  consumed.First entry should be Winner.
        entries = vm.getRecordedLogs(); //getting logs after fulfillRandomWords old logs should be gone
        bytes32 winner = entries[0].topics[1];

        //event PickedWinner(address indexed winner);

        console.log("Raffle winner is: ", raffle.getWinner());
        console.log("Emited winner is: ", address(uint160(uint256(winner))));

        //Assert
        assert(uint256(raffle.getRaffleState()) == 0); // Check raffle state is open
        assert(raffle.getWinner() != address(0)); // Should have recent winner
        assert(raffle.getLengthOfPlayers() == 0); // Should have no players
        assert(previousTimeStamp < raffle.getLastTimeStamp()); // Should have new timestamp
        assert(address(uint160(uint256(winner))) == raffle.getWinner()); // Winner should match emited winner
        assertEq(entries[0].topics[0], keccak256("PickedWinner(address)")); // Event name should match
        assertEq(
            raffle.getWinner().balance,
            STARTING_USER_BALANCE + prize - entranceFee
        ); // Winner should have prize
    }
}
