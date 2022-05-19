//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./BbxCompetition.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CompetitionFactory is Ownable {
    struct Competition {
        uint256 competitionId;
        string name;
        string description;
        string image;
        address creator;
        address contractAddress;
    }

    event CompetitionCreated(
        uint256 indexed competitionId,
        string name,
        address indexed creator,
        address contractAddress,
        string description,
        string image
    );

    Competition[] public competitions;

    constructor() {}

    function createCompetition(
        string memory name,
        string memory description,
        string memory image,
        address chainlinkToken,
        address chainlinkOracle,
        bytes32 chainlinkJobId
    ) external returns (address) {
        BeatboxCompetition bbxCompetition = new BeatboxCompetition(
            name,
            msg.sender,
            description,
            image,
            chainlinkToken,
            chainlinkOracle,
            chainlinkJobId
        );
        uint256 competitionId = competitions.length;
        address contractAddress = address(bbxCompetition);
        competitions.push(
            Competition(
                competitionId,
                name,
                description,
                image,
                msg.sender,
                contractAddress
            )
        );
        emit CompetitionCreated(
            competitionId,
            name,
            msg.sender,
            contractAddress,
            description,
            image
        );
        return contractAddress;
    }

    function getCompetitionsByCreator(address creator)
        external
        view
        returns (Competition[] memory)
    {
        uint256 totalCompetitions = 0;
        uint256 counter = 0;
        for (uint256 i = 0; i < competitions.length; i++) {
            if (competitions[i].creator == creator) {
                totalCompetitions++;
            }
        }

        Competition[] memory result = new Competition[](totalCompetitions);
        for (uint256 i = 0; i < competitions.length; i++) {
            if (competitions[i].creator == creator) {
                result[counter] = competitions[i];
                counter++;
            }
        }
        return result;
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
