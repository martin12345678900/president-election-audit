// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract RankedChoice is EIP712 {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error RankedChoice__NotTimeToVote();
    error RankedChoice__InvalidInput();
    error RankedChoice__InvalidVoter();
    error RankedChoice__SomethingWentWrong();

    /*//////////////////////////////////////////////////////////////
                           STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address private s_currentPresident; // e current president
    uint256 private s_previousVoteEndTimeStamp; // e last time a president was selected
    uint256 private s_voteNumber; // e the current vote number
    uint256 private immutable i_presidentalDuration; // e presidental duration set always as 1460 days(4 years)
    // @audit invalid TYPEHASH signiture -> should be `rankCandidates(address[])` since `rankCandidates` accepts an array of addresses
    bytes32 public constant TYPEHASH = keccak256("rankCandidates(uint256[])");
    uint256 private constant MAX_CANDIDATES = 10;

    // Solidity doesn't support contant reference types
    address[] private VOTERS;
    mapping(address voter => mapping(uint256 voteNumber => address[] orderedCandidates))
        private s_rankings;

    // For selecting the president
    address[] private s_candidateList;
    mapping(address candidate => mapping(uint256 voteNumber => mapping(uint256 roundId => uint256 votes)))
        private s_candidateVotesByRound;

    /*//////////////////////////////////////////////////////////////
                             USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory voters) EIP712("RankedChoice", "1") {
        VOTERS = voters; // set the voters (specified by the contract creator)
        i_presidentalDuration = 1460 days; // 4 years
        s_currentPresident = msg.sender; // current president is the contract creator
        s_voteNumber = 0; // it's by default 0
    }

    // @follow-up - seems ok
    function rankCandidates(address[] memory orderedCandidates) external {
        _rankCandidates(orderedCandidates, msg.sender);
    }

    // @follow-up - seems ok
    // q possible signature replay attack ???
    function rankCandidatesBySig(
        address[] memory orderedCandidates,
        bytes memory signature
    ) external {
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, orderedCandidates));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, signature);

        // q possible signature replay attack ???
        // @follow-up should not be a problem since we encode the orderedCandidates in the signiture so
        // a malicious actor can replay the signature but he needs to pass same orderedCandidates for the same voter
        _rankCandidates(orderedCandidates, signer);
    }

    // @audit-high A malicious voter can front-run this `selectPresident` function by seeing how other people ranked their candidates
    // and then rank their candidates accordingly to win the election and then immediately call this function to select the president
    function selectPresident() external {
        // e check if election time has passed
        if (
            block.timestamp - s_previousVoteEndTimeStamp <=
            i_presidentalDuration
        ) {
            revert RankedChoice__NotTimeToVote();
        }

        for (uint256 i = 0; i < VOTERS.length; i++) {
            address[] memory orderedCandidates = s_rankings[VOTERS[i]][
                s_voteNumber
            ]; // e get candidates for each voter
            for (uint256 j = 0; j < orderedCandidates.length; j++) {
                // @audit-gas - This is a nested loop, and could be expensive if the number of candidates is large
                // @audit gas - can create a copy of s_candidateList and use it to store the candidates so it does not read from the storage every time
                if (!_isInArray(s_candidateList, orderedCandidates[j])) {
                    s_candidateList.push(orderedCandidates[j]);
                }
            }
        }

        // e in the end we should have always 1 winner

        // VOTER1 = [0x1, 0x2, 0x3, 0x4, 0x5]
        // VOTER2 = [0x6, 0x7, 0x8, 0x1, 0x3]
        // s_candidateList = [0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8]
        address[] memory winnerList = _selectPresidentRecursive(
            s_candidateList,
            0
        );

        if (winnerList.length != 1) {
            revert RankedChoice__SomethingWentWrong();
        }

        // Reset the election and set President
        s_currentPresident = winnerList[0];
        s_candidateList = new address[](0);
        s_previousVoteEndTimeStamp = block.timestamp;
        s_voteNumber += 1;
    }

    /*//////////////////////////////////////////////////////////////
                           CONTRACT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
 
    // q how can we maniupate the winner ???
    function _selectPresidentRecursive(
        address[] memory candidateList, // [0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8], let's say 0x1 is in multiple rounds
        uint256 roundNumber // 0
    ) internal returns (address[] memory) {
        if (candidateList.length == 1) {
            return candidateList;
        }

        // e VOTERS will be a list of owner specified users who are able to vote for candidates(max 10)
        // Tally up the picks
        for (uint256 i = 0; i < VOTERS.length; i++) { // for example 3 VOTERS
            for (
                uint256 j = 0;
                // @audit-gas - we can use local variable to store the length of the rankings array
                j < s_rankings[VOTERS[i]][s_voteNumber].length;
                j++
            ) {
                // e get the candidate from the rankings
                address candidate = s_rankings[VOTERS[i]][s_voteNumber][j];
                // e check if the candidate is in the candidate list
                if (_isInArray(candidateList, candidate)) { // check if the candidate is in the candidate list
                    // q `s_candidateVotesByRound` is not used anywhere else in the contract so why it is a storage variable
                    s_candidateVotesByRound[candidate][s_voteNumber][
                        roundNumber
                    ] += 1;
                    break;
                } else {
                    continue;
                }
            }
        }

        // Remove the lowest candidate or break
        address fewestVotesCandidate = candidateList[0];
        uint256 fewestVotes = s_candidateVotesByRound[fewestVotesCandidate][
            s_voteNumber
        ][roundNumber];

        for (uint256 i = 1; i < candidateList.length; i++) {
            uint256 votes = s_candidateVotesByRound[candidateList[i]][
                s_voteNumber
            ][roundNumber]; // check candadata votes
            if (votes < fewestVotes) { // check if the votes are less than the fewest votes
                fewestVotes = votes;
                fewestVotesCandidate = candidateList[i];
            }
        }

        address[] memory newCandidateList = new address[](
            candidateList.length - 1
        );

        bool passedCandidate = false;
        for (uint256 i; i < candidateList.length; i++) {
            if (passedCandidate) {
                newCandidateList[i - 1] = candidateList[i];
            } else if (candidateList[i] == fewestVotesCandidate) {
                passedCandidate = true;
            } else {
                newCandidateList[i] = candidateList[i];
            }
        }

        return _selectPresidentRecursive(newCandidateList, roundNumber + 1);
    }

    // @follow-up - seems ok
    function _rankCandidates(
        address[] memory orderedCandidates, // [0x01234, 0x05678, 0x0910113]
        address voter // 0x12345
    ) internal {
        // Checks
        // @audit We can pass in orderCardidates same address multiple times [0x1, 0x1, 0x1, ...MAX_CANDIDATES]
        // @audit we can pass our own voter address as a candidate // [myAddress, 0x1, 0x2, 0x3]
        if (orderedCandidates.length > MAX_CANDIDATES) { // e check if the number of candidates is greater than the max
            revert RankedChoice__InvalidInput();
        }
        if (!_isInArray(VOTERS, voter)) { // e check if the specified voter is in the list of voters
            revert RankedChoice__InvalidVoter();
        }

        // if (!_isInArray(orderedCandidates, voter)) {
        //     revert();
        // }

        // Internal Effects
        s_rankings[voter][s_voteNumber] = orderedCandidates;
    }

    // @follow-up - seems ok
    function _isInArray(
        address[] memory array,
        address someAddress
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == someAddress) {
                return true;
            }
        }
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function getUserCurrentVote(
        address voter
    ) external view returns (address[] memory) {
        return s_rankings[voter][s_voteNumber];
    }

    function getDuration() external view returns (uint256) {
        return i_presidentalDuration;
    }

    function getCurrentPresident() external view returns (address) {
        return s_currentPresident;
    }
}
