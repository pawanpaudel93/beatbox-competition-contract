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
    using Counters for Counters.Counter;
    using Chainlink for Chainlink.Request;

    // Chainlink Oracle and Job ID
    uint256 private constant ORACLE_PAYMENT =
        ((0 * LINK_DIVISIBILITY) / 100) * 5;
    bytes32 internal jobId;

    // Chainlink VRF
    VRFCoordinatorV2Interface internal COORDINATOR;
    uint64 public subscriptionId;
    bytes32 internal keyHash;
    uint32 private callbackGasLimit = 450000;
    uint16 private requestConfirmations = 3;
    uint32 private numWords = 1;
    mapping(uint256 => bool) private isRequestValid;

    event WinnerSelected(uint256 battleId, uint256 winnerId);
    event RandomNumberRequested(uint256 requestId);
    event OpponentsSelected(CompetitionState state);

    function addBeatboxers(
        address[] calldata beatboxerAddresses,
        string[] calldata names
    ) external isAdminOrHelper {
        require(
            metaData.competitionState == CompetitionState.WILDCARD_SELECTION,
            "CompetitionStateMismatch"
        );
        require(judgeCount.current() > 0, "NoJudge");
        require(beatboxers.length == 0, "BeatboxersAlreadyExist");
        require(beatboxerAddresses.length == names.length, "LengthMismatch");
        require(
            beatboxerAddresses.length == BEATBOXERS_COUNT,
            "TopSixteenBeatboxersOnly"
        );
        for (uint256 i = 0; i < beatboxerAddresses.length; i++) {
            if (hasRole(JUDGE_ROLE, beatboxerAddresses[i])) {
                revert("JudgeCannotBeBeatboxer");
            }
            competitionStateToBeatboxerIds[CompetitionState.TOP_SIXTEEN].push(
                beatboxers.length
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
        for (uint256 i; i < shuffledBeatboxersIds.length; i += 2) {
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
        // Check if battle is over
        // Keeper will perform upkeep if both judges have voted and battle is over or if all judges havenot voted but battle is over.
        upkeepNeeded =
            (s_upkeepNeeded && battles[battleId].endTime <= block.timestamp) ||
            (battles[battleId].endTime <= block.timestamp &&
                battles[battleId].winnerId == BEATBOXERS_COUNT);
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        uint256 battleId = battles.length - 1;
        if (
            (s_upkeepNeeded && battles[battleId].endTime <= block.timestamp) ||
            (battles[battleId].endTime <= block.timestamp &&
                battles[battleId].winnerId == BEATBOXERS_COUNT)
        ) {
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
        uint256 likeCount1,
        uint256 likeCount2
    ) public recordChainlinkFulfillment(requestId) {
        uint256 battleId = battles.length - 1;
        Battle storage battle = battles[battleId];
        CompetitionState currentState = metaData.competitionState;
        competitionStateToBattleOpponents[currentState][battle.stateBattleId]
            .isCompleted = true;
        battle.beatboxerOne.likeCount = likeCount1;
        battle.beatboxerTwo.likeCount = likeCount2;
        if (likeCount1 > likeCount2) {
            battle.beatboxerOne.score += 1;
        } else if (likeCount1 < likeCount2) {
            battle.beatboxerTwo.score += 1;
        }
        uint256 winnerId;
        if (battle.beatboxerOne.score > battle.beatboxerTwo.score) {
            winnerId = battle.beatboxerOne.beatboxerId;
        } else if (battle.beatboxerOne.score < battle.beatboxerTwo.score) {
            winnerId = battle.beatboxerTwo.beatboxerId;
        } else {
            uint256 randomIndex = uint256(
                keccak256(abi.encode(requestId, likeCount1, likeCount2))
            ) % 2;
            winnerId = [
                battle.beatboxerOne.beatboxerId,
                battle.beatboxerTwo.beatboxerId
            ][randomIndex];
        }
        battle.winnerId = winnerId;
        competitionStateToBeatboxerIds[
            CompetitionState(uint256(currentState) + 1)
        ].push(winnerId);
        battleCountByState[currentState] += 1;

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
            uint256[] memory beatboxersIds = competitionStateToBeatboxerIds[
                metaData.competitionState
            ];
            competitionStateToBattleOpponents[metaData.competitionState].push(
                BattleOpponent(beatboxersIds[0], beatboxersIds[1], false)
            );
        } else if (
            currentState == CompetitionState.FINAL &&
            battleCountByState[currentState] == 1
        ) {
            metaData.competitionState = CompetitionState.COMPLETED;
        }
        if (battle.winningAmount > 0) {
            (bool sent, ) = beatboxers[winnerId].beatboxerAddress.call{
                value: battle.winningAmount
            }("");
            require(sent, "PaymentNotSent");
        }
        emit WinnerSelected(battleId, battle.winnerId);
    }

    function _randomNumberRequest() internal {
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        isRequestValid[requestId] = true;
        emit RandomNumberRequested(requestId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        require(isRequestValid[requestId], "InvalidRequest");
        delete isRequestValid[requestId];
        _setBattleOpponents(randomWords[0]);
        emit OpponentsSelected(metaData.competitionState);
    }

    function setSubscriptionId(uint64 _subscriptionId) external isAdmin {
        subscriptionId = _subscriptionId;
    }
}
