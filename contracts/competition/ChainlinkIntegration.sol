//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "./CompetitionBase.sol";

abstract contract ChainlinkIntegration is
    CompetitionBase,
    ChainlinkClient,
    KeeperCompatibleInterface,
    VRFConsumerBaseV2
{
    using Chainlink for Chainlink.Request;

    // Chainlink Oracle and Job ID
    uint256 private constant ORACLE_PAYMENT =
        ((0 * LINK_DIVISIBILITY) / 100) * 5;
    bytes32 internal jobId;

    // Chainlink VRF
    VRFCoordinatorV2Interface internal COORDINATOR;
    uint64 private subscriptionId;
    bytes32 internal keyHash;
    uint32 private callbackGasLimit = 100000;
    uint16 private requestConfirmations = 3;
    uint32 private numWords = 1;

    function addBeatboxers(
        address[] calldata beatboxerAddresses,
        string[] calldata names
    ) external isAdminOrHelper {
        require(
            metaData.competitionState == CompetitionState.WILDCARD_SELECTION,
            "CompetitionStateMismatch"
        );
        require(beatboxers.length == 0, "BeatboxersAlreadyExist");
        require(beatboxerAddresses.length == names.length, "LengthMismatch");
        require(
            beatboxerAddresses.length == BEATBOXERS_COUNT,
            "TopSixteenBeatboxersOnly"
        );
        for (uint256 i = 0; i < beatboxerAddresses.length; i++) {
            uint256 beatboxerId = beatboxers.length;
            beatboxerIndexByAddress[beatboxerAddresses[i]] = beatboxerId;
            competitionStateToBeatboxerIds[CompetitionState.TOP_SIXTEEN].push(
                beatboxerId
            );
            beatboxers.push(Beatboxer(names[i], beatboxerAddresses[i]));
        }
        metaData.competitionState = CompetitionState.TOP_SIXTEEN;
        _randomNumberRequest();
        emit BeatboxersAdded();
    }

    function _randomlyShuffle(uint256[] memory array, uint256 seed)
        private
        pure
        returns (uint256[] memory)
    {
        uint256 arrayLength = array.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            uint256 j = uint256(keccak256(abi.encode(seed, i))) % arrayLength;
            uint256 temp = array[i];
            array[i] = array[j];
            array[j] = temp;
        }
        return array;
    }

    function _setBattleOpponents(uint256 randomNumber) internal {
        uint256[] memory beatboxersIds = competitionStateToBeatboxerIds[
            metaData.competitionState
        ];
        uint256[] memory shuffledBeatboxersIds = _randomlyShuffle(
            beatboxersIds,
            randomNumber
        );
        for (uint256 i; i < (shuffledBeatboxersIds.length / 2); i = i + 2) {
            competitionStateToBattleOpponents[metaData.competitionState].push(
                BattleOpponent(
                    shuffledBeatboxersIds[i],
                    shuffledBeatboxersIds[i + 1],
                    false
                )
            );
        }
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        uint256 battleId = battles.length > 0 ? battles.length - 1 : 0;
        upkeepNeeded =
            s_upkeepNeeded &&
            battles[battleId].endTime <= block.timestamp;
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        uint256 battleId = battles.length - 1;
        if (s_upkeepNeeded && battles[battleId].endTime <= block.timestamp) {
            s_upkeepNeeded = false;
            Battle storage battle = battles[battleId];
            string memory tags = string(
                abi.encodePacked(
                    battle.beatboxerOne.ytVideoId,
                    ",",
                    battle.beatboxerTwo.ytVideoId
                )
            );
            Chainlink.Request memory req = buildChainlinkRequest(
                jobId,
                address(this),
                this.fulfillValue1AndValue2.selector
            );
            req.add("tags", tags);
            sendOperatorRequest(req, ORACLE_PAYMENT);
        }
    }

    function fulfillValue1AndValue2(
        bytes32 requestId,
        uint256 likeCount2,
        uint256 likeCount1
    ) public recordChainlinkFulfillment(requestId) {
        uint256 battleId = battles.length - 1;
        Battle storage battle = battles[battleId];
        if (likeCount1 > likeCount2) {
            battle.beatboxerOne.score += 1;
        } else if (likeCount1 < likeCount2) {
            battle.beatboxerTwo.score += 1;
        }
        address winnerAddress;
        CompetitionState currentState = metaData.competitionState;
        if (battle.beatboxerOne.score > battle.beatboxerTwo.score) {
            winnerAddress = battle.beatboxerOne.beatboxerAddress;
            battle.beatboxerOne.likeCount = likeCount1;
            battle.winnerAddress = winnerAddress;
            competitionStateToBeatboxerIds[currentState].push(
                beatboxerIndexByAddress[winnerAddress]
            );
            balances[winnerAddress] += battle.winningAmount;
        } else if (battle.beatboxerOne.score < battle.beatboxerTwo.score) {
            winnerAddress = battle.beatboxerTwo.beatboxerAddress;
            battle.beatboxerTwo.likeCount = likeCount2;
            battle.winnerAddress = winnerAddress;
            competitionStateToBeatboxerIds[currentState].push(
                beatboxerIndexByAddress[winnerAddress]
            );
            balances[winnerAddress] += battle.winningAmount;
        }
        if (winnerAddress != address(0)) {
            battleCountByState[currentState] += 1;
        }
        if (
            currentState == CompetitionState.TOP_SIXTEEN &&
            battleCountByState[currentState] == 8
        ) {
            metaData.competitionState = CompetitionState.TOP_EIGHT;
            _randomNumberRequest();
        } else if (
            currentState == CompetitionState.TOP_EIGHT &&
            battleCountByState[currentState] == 4
        ) {
            metaData.competitionState = CompetitionState.SEMIFINAL;
            _randomNumberRequest();
        } else if (
            currentState == CompetitionState.SEMIFINAL &&
            battleCountByState[currentState] == 2
        ) {
            metaData.competitionState = CompetitionState.FINAL;
        } else if (
            currentState == CompetitionState.FINAL &&
            battleCountByState[currentState] == 1
        ) {
            metaData.competitionState = CompetitionState.COMPLETED;
        }
        emit WinnerSelected(battleId, battle.winnerAddress);
    }

    function _randomNumberRequest() internal {
        COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
    }

    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        _setBattleOpponents(randomWords[0]);
    }

    function setSubscriptionId(uint64 _subscriptionId) external isAdmin {
        subscriptionId = _subscriptionId;
    }
}
