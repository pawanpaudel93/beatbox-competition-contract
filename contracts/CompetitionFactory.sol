//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./competition/BeatboxCompetition.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CompetitionFactory is Ownable {
    using Counters for Counters.Counter;

    address private immutable CHAINLINK_VRF_COORDINATOR;
    address private immutable CHAINLINK_TOKEN;
    address private immutable CHAINLINK_ORACLE;
    bytes32 private immutable CHAINLINK_JOBID;
    bytes32 private immutable CHAINLINK_KEYHASH;

    event CompetitionCreated(
        uint256 indexed competitionId,
        address indexed creator,
        address contractAddress,
        bytes32 name,
        string description,
        string imageURI
    );
    Counters.Counter public totalCompetitions;

    constructor(
        address chainlinkToken,
        address chainlinkOracle,
        address vrfCoordinator,
        bytes32 chainlinkJobId,
        bytes32 chainlinkKeyhash
    ) {
        CHAINLINK_TOKEN = chainlinkToken;
        CHAINLINK_ORACLE = chainlinkOracle;
        CHAINLINK_JOBID = chainlinkJobId;
        CHAINLINK_VRF_COORDINATOR = vrfCoordinator;
        CHAINLINK_KEYHASH = chainlinkKeyhash;
    }

    function createCompetition(
        bytes32 name,
        string memory description,
        string memory imageURI
    ) external returns (address) {
        BeatboxCompetition bbxCompetition = new BeatboxCompetition(
            name,
            msg.sender,
            description,
            imageURI,
            CHAINLINK_TOKEN,
            CHAINLINK_ORACLE,
            CHAINLINK_VRF_COORDINATOR,
            CHAINLINK_JOBID,
            CHAINLINK_KEYHASH
        );
        uint256 competitionId = totalCompetitions.current();
        address contractAddress = address(bbxCompetition);
        totalCompetitions.increment();
        emit CompetitionCreated(
            competitionId,
            msg.sender,
            contractAddress,
            name,
            description,
            imageURI
        );
        return contractAddress;
    }

    function withdraw() external onlyOwner {
        (bool sent, ) = owner().call{value: address(this).balance}("");
        require(sent, "Not enough funds");
    }

    receive() external payable {
        // Do nothing
    }

    fallback() external payable {
        // Do nothing
    }
}
