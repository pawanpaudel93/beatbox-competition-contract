//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ChainlinkIntegration.sol";

contract BeatboxCompetition is ChainlinkIntegration {
    constructor(
        bytes32 name,
        address contractOwner,
        string memory description,
        string memory imageURI,
        address chainlinkToken,
        address chainlinkOracle,
        address vrfCoordinator,
        bytes32 chainlinkJobId,
        bytes32 chainlinkKeyhash
    ) VRFConsumerBaseV2(vrfCoordinator) {
        metaData = MetaData(
            name,
            imageURI,
            description,
            CompetitionState.NOT_STARTED
        );
        _setupRole(DEFAULT_ADMIN_ROLE, contractOwner);
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        setChainlinkToken(chainlinkToken);
        setChainlinkOracle(chainlinkOracle);
        keyHash = chainlinkKeyhash;
        jobId = chainlinkJobId;
    }

    receive() external payable {
        // Do nothing
    }

    fallback() external payable {
        // Do nothing
    }
}
