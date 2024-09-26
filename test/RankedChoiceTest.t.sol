// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {RankedChoice} from "src/RankedChoice.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract RankedChoiceTest is Test {
    address[] voters;
    uint256[] voterPrivateKeys;

    address[] candidates;

    uint256 constant MAX_VOTERS = 100;
    uint256 constant MAX_CANDIDATES = 20;
    uint256 constant VOTERS_ADDRESS_MODIFIER = 100;
    uint256 constant CANDIDATES_ADDRESS_MODIFIER = 200;

    RankedChoice rankedChoice;

    address[] orderedCandidates;

    function setUp() public {
        for (uint256 i = 0; i < MAX_VOTERS; i++) {
            uint256 voterPrivateKey = uint256(keccak256(abi.encodePacked("dummy mnemonic", uint256(1))));
            address voter = vm.addr(voterPrivateKey);
            voterPrivateKeys.push(voterPrivateKey);
            voters.push(voter);
        }
        rankedChoice = new RankedChoice(voters);

        for (uint256 i = 0; i < MAX_CANDIDATES; i++) {
            candidates.push(address(uint160(i + CANDIDATES_ADDRESS_MODIFIER)));
        }
    }

    function testVote() public {
        orderedCandidates = [candidates[0], candidates[1], candidates[2]];
        vm.prank(voters[0]);
        rankedChoice.rankCandidates(orderedCandidates);

        assertEq(rankedChoice.getUserCurrentVote(voters[0]), orderedCandidates);
    }

    function testSelectPresident() public {
        assert(rankedChoice.getCurrentPresident() != candidates[0]);

        orderedCandidates = [candidates[0], candidates[1], candidates[2]];
        uint256 startingIndex = 0;
        uint256 endingIndex = 60;
        for (uint256 i = startingIndex; i < endingIndex; i++) {
            vm.prank(voters[i]);
            rankedChoice.rankCandidates(orderedCandidates);
        }

        startingIndex = endingIndex + 1;
        endingIndex = 100;
        orderedCandidates = [candidates[3], candidates[1], candidates[4]];
        for (uint256 i = startingIndex; i < endingIndex; i++) {
            vm.prank(voters[i]);
            rankedChoice.rankCandidates(orderedCandidates);
        }

        vm.warp(block.timestamp + rankedChoice.getDuration());

        rankedChoice.selectPresident();
        assertEq(rankedChoice.getCurrentPresident(), candidates[0]);
    }

    function testSelectPresidentWhoIsSecondMostPopular() public {
        assert(rankedChoice.getCurrentPresident() != candidates[0]);

        orderedCandidates = [candidates[0], candidates[1], candidates[2]];
        uint256 startingIndex = 0;
        uint256 endingIndex = 24;
        for (uint256 i = startingIndex; i < endingIndex; i++) {
            vm.prank(voters[i]);
            rankedChoice.rankCandidates(orderedCandidates);
        }

        startingIndex = endingIndex + 1;
        endingIndex = 49;
        orderedCandidates = [candidates[3], candidates[1], candidates[4]];
        for (uint256 i = startingIndex; i < endingIndex; i++) {
            vm.prank(voters[i]);
            rankedChoice.rankCandidates(orderedCandidates);
        }

        startingIndex = endingIndex + 1;
        endingIndex = 74;
        orderedCandidates = [candidates[7], candidates[1], candidates[10]];
        for (uint256 i = 0; i < MAX_VOTERS / 3; i++) {
            vm.prank(voters[i]);
            rankedChoice.rankCandidates(orderedCandidates);
        }

        startingIndex = endingIndex + 1;
        endingIndex = 82;
        orderedCandidates = [candidates[12], candidates[1], candidates[18]];
        for (uint256 i = 0; i < MAX_VOTERS / 3; i++) {
            vm.prank(voters[i]);
            rankedChoice.rankCandidates(orderedCandidates);
        }

        startingIndex = endingIndex + 1;
        endingIndex = 100;
        orderedCandidates = [candidates[1], candidates[9], candidates[11]];
        for (uint256 i = 0; i < MAX_VOTERS / 3; i++) {
            vm.prank(voters[i]);
            rankedChoice.rankCandidates(orderedCandidates);
        }

        vm.warp(block.timestamp + rankedChoice.getDuration());

        rankedChoice.selectPresident();
        assertEq(rankedChoice.getCurrentPresident(), candidates[1]);
    }

    // function testNonVoterIsAbleToOverrideVotersCandidates() public {
    //     orderedCandidates = [candidates[0], candidates[1], candidates[2]];
    //     vm.prank(voters[0]);
    //     rankedChoice.rankCandidates(orderedCandidates);

    //     bytes32 domainSeparator = keccak256(abi.encode(
    //         keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
    //         keccak256(bytes("RankedChoice")),  // Name of the contract
    //         keccak256(bytes("1")),             // Version of the contract
    //         block.chainid,                     // Chain ID (use vm.chainId() for Foundry)
    //         address(rankedChoice)              // The address of the deployed contract
    //     ));

    //     bytes32 structHash = keccak256(abi.encode(rankedChoice.TYPEHASH(), orderedCandidates));
    //     bytes32 hash =  MessageHashUtils.toTypedDataHash(domainSeparator, structHash); // Use the same hash method as in the contract
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(voterPrivateKeys[0], hash);
    //     bytes memory signature = abi.encodePacked(r, s, v);


    //     address attacker = makeAddr("attacker");
    //     vm.startPrank(attacker);
    //     // orderedCandidates = [candidates[3], candidates[1], candidates[4]];
    //     rankedChoice.rankCandidatesBySig(orderedCandidates, signature);
    //     vm.stopPrank();
    // }

function testFrontRunPresidentSelection() public {
    orderedCandidates = [candidates[1], candidates[2], candidates[3]];
    vm.prank(voters[0]);
    rankedChoice.rankCandidates(orderedCandidates);

    // Voter 1 ranks candidate[3], candidate[2], candidate[1]
    orderedCandidates = [candidates[3], candidates[2], candidates[1]];
    vm.prank(voters[1]);
    rankedChoice.rankCandidates(orderedCandidates);

    // Voter 2 ranks candidate[2], candidate[1], candidate[3]
    orderedCandidates = [candidates[2], candidates[1], candidates[3]];
    vm.prank(voters[2]);
    rankedChoice.rankCandidates(orderedCandidates);

    // --- FRONT-RUNNING BEGINS ---
    // Front-runner (Voter 3) spends extra gas (simulated here) to ensure their transaction is mined before `selectPresident`
    // We simulate this by placing their `rankCandidates` call immediately before `selectPresident`

    // Front-runner logic: Rank candidates strategically to favor `candidate[0]`
    orderedCandidates = [candidates[0], candidates[3], candidates[2]];

    // Simulate spending extra gas by adding a loop before casting vote (artificial gas consumption)
    uint256 fakeGasSpend = 0;
    for (uint256 i = 0; i < 1000; i++) {
        fakeGasSpend += i; // Simulate some gas-intensive operation
    }

    vm.prank(voters[3]); // Front-runner casts their manipulated vote
    rankedChoice.rankCandidates(orderedCandidates);

    // Move time forward to simulate end of the voting period
    vm.warp(block.timestamp + rankedChoice.getDuration());

    // Select the president
    rankedChoice.selectPresident();

    // Verify that the front-runner's candidate (candidate[0]) won due to strategic voting
    console.log("Selected President: ", rankedChoice.getCurrentPresident());
    assertEq(rankedChoice.getCurrentPresident(), candidates[0]); // candidate[0] is the manipulated winner
}
}
