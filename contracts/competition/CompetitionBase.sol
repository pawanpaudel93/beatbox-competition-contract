//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract CompetitionBase is AccessControl {
    using Counters for Counters.Counter;

    bytes32 internal constant HELPER_ROLE = keccak256("HELPER_ROLE");
    bytes32 internal constant JUDGE_ROLE = keccak256("JUDGE_ROLE");
    uint256 internal constant BEATBOXERS_COUNT = 16;
    uint256 internal constant JUDGES_MIN_COUNT = 2;

    struct Beatboxer {
        string name;
        address beatboxerAddress;
    }

    struct BattleBeatboxer {
        bytes11 ytVideoId;
        uint8 score;
        uint256 beatboxerId;
        uint256 likeCount;
    }

    struct Point {
        uint8 originality;
        uint8 pitchAndTiming;
        uint8 complexity;
        uint8 enjoymentOfListening;
        uint8 video;
        uint8 audio;
        uint8 battle;
        uint8 extraPoint;
        address votedBy;
        uint256 votedFor;
    }

    struct Battle {
        BattleBeatboxer beatboxerOne;
        BattleBeatboxer beatboxerTwo;
        uint256 winnerId;
        uint256 startTime;
        uint256 endTime;
        uint256 winningAmount;
        CompetitionState state;
        string name;
    }

    struct BattleOpponent {
        uint256 beatboxerOneId;
        uint256 beatboxerTwoId;
        bool isStarted;
    }

    struct MetaData {
        bytes32 name;
        string imageURI;
        string description;
        CompetitionState competitionState;
    }

    enum CompetitionState {
        NOT_STARTED,
        WILDCARD_SUBMISSION,
        WILDCARD_SELECTION,
        TOP_SIXTEEN,
        TOP_EIGHT,
        SEMIFINAL,
        FINAL,
        COMPLETED
    }

    MetaData public metaData;
    Battle[] public battles;
    Beatboxer[BEATBOXERS_COUNT] public beatboxers;
    Counters.Counter public judgeCount;
    bool public s_upkeepNeeded;

    mapping(CompetitionState => uint256[]) competitionStateToBeatboxerIds;
    mapping(CompetitionState => uint256) public battleCountByState;
    mapping(uint256 => mapping(address => bool)) public judgeVoted;
    mapping(uint256 => Point[]) public pointsByBattle;
    mapping(CompetitionState => BattleOpponent[])
        public competitionStateToBattleOpponents;

    event BattleCreated(uint256 id, string name, CompetitionState state);
    event BeatboxersAdded();
    event BeatboxerRemoved(address beatboxerAddress);
    event JudgeAdded(address judgeAddress, string name);
    event JudgeRemoved(address judgeAddress);
    event HelperAdded(address helperAddress, string name);
    event HelperRemoved(address helperAddress);
    event BattleVoted(uint256 battleId, address votedBy);

    modifier isAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        _;
    }

    modifier isHelper() {
        if (!hasRole(HELPER_ROLE, msg.sender)) revert NotHelper();
        _;
    }

    modifier isJudge() {
        if (!hasRole(JUDGE_ROLE, msg.sender)) revert NotJudge();
        _;
    }

    modifier isAdminOrHelper() {
        if (
            !hasRole(DEFAULT_ADMIN_ROLE, msg.sender) &&
            !hasRole(HELPER_ROLE, msg.sender)
        ) revert NotAdminOrHelper();
        _;
    }

    error NotAdmin();
    error NotHelper();
    error NotJudge();
    error NotAdminOrHelper();

    function startBattle(
        uint256 stateBattleId,
        string memory name,
        bytes11 ytVideoIdOne,
        bytes11 ytVideoIdTwo,
        uint256 startTime,
        uint256 endTime,
        uint256 winningAmount
    ) external isAdmin {
        require(address(this).balance >= winningAmount, "Not enough funds");
        CompetitionState state = metaData.competitionState;
        BattleOpponent
            memory battleOpponent = competitionStateToBattleOpponents[state][
                stateBattleId
            ];
        require(!battleOpponent.isStarted, "Battle already started");
        require(endTime > startTime, "Endtime before starttime");
        competitionStateToBattleOpponents[state][stateBattleId]
            .isStarted = true;
        uint256 battleId = battles.length;
        battles.push(
            Battle(
                BattleBeatboxer(
                    ytVideoIdOne,
                    0,
                    battleOpponent.beatboxerOneId,
                    0
                ),
                BattleBeatboxer(
                    ytVideoIdTwo,
                    0,
                    battleOpponent.beatboxerTwoId,
                    0
                ),
                BEATBOXERS_COUNT,
                startTime,
                endTime,
                winningAmount,
                state,
                name
            )
        );
        emit BattleCreated(battleId, name, state);
    }

    function voteBattle(
        uint256 battleId,
        Point calldata point1,
        Point calldata point2
    ) external isJudge {
        require(battleId < battles.length, "Battle not found");
        Battle storage battle = battles[battleId];
        require(battle.winnerId == BEATBOXERS_COUNT, "Battle already over");
        require(battle.startTime <= block.timestamp, "Battle not started");
        require(battle.endTime >= block.timestamp, "Battle already over");
        require(!judgeVoted[battleId][msg.sender], "Judge already voted");
        judgeVoted[battleId][msg.sender] = true;
        battle.beatboxerOne.score += _calculateScore(point1);
        battle.beatboxerTwo.score += _calculateScore(point2);
        pointsByBattle[battleId].push(point1);
        pointsByBattle[battleId].push(point2);
        if (judgeCount.current() * 2 == pointsByBattle[battleId].length) {
            s_upkeepNeeded = true;
        }
        emit BattleVoted(battleId, msg.sender);
    }

    function _calculateScore(Point calldata point)
        private
        pure
        returns (uint8)
    {
        return
            point.originality +
            point.pitchAndTiming +
            point.complexity +
            point.enjoymentOfListening +
            point.video +
            point.audio +
            point.battle +
            point.extraPoint;
    }

    function addJudge(address judgeAddress, string memory name)
        external
        isAdminOrHelper
    {
        require(
            metaData.competitionState <= CompetitionState.WILDCARD_SELECTION,
            "Cannot add judge"
        );
        require(!hasRole(JUDGE_ROLE, judgeAddress), "Judge already exists");
        _setupRole(JUDGE_ROLE, judgeAddress);
        judgeCount.increment();
        emit JudgeAdded(judgeAddress, name);
    }

    function removeJudge(address judgeAddress) external isAdminOrHelper {
        require(
            metaData.competitionState <= CompetitionState.WILDCARD_SELECTION,
            "Cannot remove judge"
        );
        require(hasRole(JUDGE_ROLE, judgeAddress), "Judge not found");
        _revokeRole(JUDGE_ROLE, judgeAddress);
        judgeCount.decrement();
        emit JudgeRemoved(judgeAddress);
    }

    function addHelper(address helperAddress, string memory name)
        external
        isAdminOrHelper
    {
        require(!hasRole(HELPER_ROLE, helperAddress), "Helper already exists");
        _setupRole(HELPER_ROLE, helperAddress);
        emit HelperAdded(helperAddress, name);
    }

    function removeHelper(address helperAddress) external isAdminOrHelper {
        require(hasRole(HELPER_ROLE, helperAddress), "Helper not found");
        _revokeRole(HELPER_ROLE, helperAddress);
        emit HelperRemoved(helperAddress);
    }

    function setName(bytes32 name) external isAdmin {
        metaData.name = name;
    }

    function setDescription(string memory description) external isAdmin {
        metaData.description = description;
    }

    function setImage(string memory imageURI) external isAdmin {
        metaData.imageURI = imageURI;
    }

    function startWildcard() external isAdmin {
        require(
            metaData.competitionState == CompetitionState.NOT_STARTED,
            "Competition already started"
        );
        metaData.competitionState = CompetitionState.WILDCARD_SUBMISSION;
    }

    function endWildcard() external isAdmin {
        require(
            metaData.competitionState == CompetitionState.WILDCARD_SUBMISSION,
            "Competition not started"
        );
        metaData.competitionState = CompetitionState.WILDCARD_SELECTION;
    }

    function withdraw(uint256 amount) external isAdmin {
        uint256 battlesCount = battles.length;
        require(
            (metaData.competitionState <= CompetitionState.TOP_SIXTEEN &&
                battlesCount == 0) ||
                battlesCount == 0 ||
                (battlesCount > 0 &&
                    battles[battlesCount - 1].winnerId != BEATBOXERS_COUNT),
            "Battles still in progress"
        );
        require(address(this).balance >= amount, "Insufficient balance");
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Failed to Send");
    }

    function getAllBattles() external view returns (Battle[] memory) {
        return battles;
    }

    function getCurrentOpponents()
        external
        view
        returns (Beatboxer[2][] memory)
    {
        uint256 battlesCount;
        uint256 counter;

        BattleOpponent[]
            memory battleOpponents = competitionStateToBattleOpponents[
                metaData.competitionState
            ];

        for (uint256 i; i < battleOpponents.length; i++) {
            if (!battleOpponents[i].isStarted) {
                battlesCount++;
            }
        }

        Beatboxer[2][] memory currentOpponents = new Beatboxer[2][](
            battlesCount
        );
        for (uint256 i; i < battleOpponents.length; i++) {
            if (!battleOpponents[i].isStarted) {
                currentOpponents[counter] = [
                    beatboxers[battleOpponents[i].beatboxerOneId],
                    beatboxers[battleOpponents[i].beatboxerTwoId]
                ];
                counter++;
            }
        }
        return currentOpponents;
    }

    function getVotedBattlesIndices(address judge)
        external
        view
        returns (uint256[] memory)
    {
        if (!hasRole(JUDGE_ROLE, judge)) {
            return new uint256[](0);
        }
        uint256 indicesCount;
        uint256 counter;
        for (uint256 i = 0; i < battles.length; i++) {
            if (judgeVoted[i][judge]) {
                indicesCount++;
            }
        }
        uint256[] memory votedBattlesIndices = new uint256[](indicesCount);
        for (uint256 i = 0; i < battles.length; i++) {
            if (judgeVoted[i][judge]) {
                votedBattlesIndices[counter] = i;
                counter++;
            }
        }
        return votedBattlesIndices;
    }

    function getRoles(address _address) external view returns (bool[] memory) {
        bool[] memory roles = new bool[](3);
        if (hasRole(DEFAULT_ADMIN_ROLE, _address)) {
            roles[0] = true;
        }
        if (hasRole(HELPER_ROLE, _address)) {
            roles[1] = true;
        }
        if (hasRole(JUDGE_ROLE, _address)) {
            roles[2] = true;
        }
        return roles;
    }

    function getBattlePoints(uint256 battleId)
        external
        view
        returns (Point[] memory)
    {
        return pointsByBattle[battleId];
    }
}
