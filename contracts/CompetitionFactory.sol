//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./BbxCompetition.sol";

// import "@openzeppelin/contracts/utils/Counters.sol";

contract CompetitionFactory {
    // using Counters for Counters.Counter;

    struct Competition {
        string name;
        address contractAddress;
    }

    Competition[] public competitions;

    event CompetitionCreated(uint256 id, string name);

    constructor() {}

    function createCompetition(string memory name) public returns (address) {
        BbxCompetition bbxCompetition = new BbxCompetition(name, msg.sender);
        address contractAddress = address(bbxCompetition);
        uint256 competitionId = competitions.length;
        competitions.push(
            Competition({name: name, contractAddress: contractAddress})
        );
        emit CompetitionCreated(competitionId, name);
        return contractAddress;
    }

    receive() external payable {
        // Do nothing
    }

    fallback() external payable {
        // Do nothing
    }
}
