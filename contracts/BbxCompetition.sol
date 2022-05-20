//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

contract BeatboxCompetition is
    AccessControl,
    ChainlinkClient,
    KeeperCompatibleInterface
{
    using Counters for Counters.Counter;
    using Chainlink for Chainlink.Request;

    uint256 private constant ORACLE_PAYMENT =
        ((0 * LINK_DIVISIBILITY) / 100) * 5;
    bytes32 private immutable jobId;
    bytes32 private constant HELPER_ROLE = keccak256("HELPER_ROLE");
    bytes32 private constant JUDGE_ROLE = keccak256("JUDGE_ROLE");

    struct Beatboxer {
        string name;
        address beatboxerAddress;
        uint8 latestScore;
    }

    struct BattleBeatboxer {
        bytes11 ytVideoId;
        address beatboxerAddress;
        uint8 score;
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
        address votedFor;
    }

    struct Battle {
        uint256 id;
        BattleBeatboxer beatboxerOne;
        BattleBeatboxer beatboxerTwo;
        address winnerAddress;
        uint256 startTime;
        uint256 endTime;
        uint256 winningAmount;
        CompetitionState category;
        string name;
    }

    struct MetaData {
        string name;
        string description;
        string image;
        CompetitionState competitionState;
    }

    enum CompetitionState {
        NOT_STARTED,
        WILDCARD,
        TOP16,
        TOP8,
        SEMIFINAL,
        FINAL,
        COMPLETED
    }

    MetaData public metaData;
    Battle[] public battles;
    Beatboxer[] public beatboxers;
    Counters.Counter public judgeCount;
    mapping(address => uint256) private beatboxerIndexByAddress;
    mapping(CompetitionState => mapping(address => bool))
        private beatboxerSelectedByCategory;
    mapping(uint256 => mapping(address => bool)) public judgeVoted;
    mapping(uint256 => Point[]) public pointsByBattle;
    mapping(uint256 => bool) private battleIdToUpkeepNeeded;

    event BattleCreated(uint256 id, string name, CompetitionState category);
    event BeatboxerAdded(address beatboxerAddress, string name);
    event BeatboxerRemoved(address beatboxerAddress);
    event JudgeAdded(address judgeAddress, string name);
    event JudgeRemoved(address judgeAddress);
    event WinnerSelected(uint256 battleId, address winnerAddress);

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

    constructor(
        string memory name,
        address contractOwner,
        string memory description,
        string memory image,
        address chainlinkToken,
        address chainlinkOracle,
        bytes32 chainlinkJobId
    ) {
        metaData = MetaData(
            name,
            description,
            image,
            CompetitionState.NOT_STARTED
        );
        _setupRole(DEFAULT_ADMIN_ROLE, contractOwner);
        setChainlinkToken(chainlinkToken);
        setChainlinkOracle(chainlinkOracle);
        jobId = chainlinkJobId;
    }

    function startBattle(
        string memory name,
        CompetitionState category,
        address beatboxerOneAddress,
        address beatboxerTwoAddress,
        bytes11 ytVideoIdOne,
        bytes11 ytVideoIdTwo,
        uint256 startTime,
        uint256 endTime,
        uint256 winningAmount
    ) external isAdmin {
        require(
            metaData.competitionState > CompetitionState.WILDCARD,
            "BattleNotStarted"
        );
        require(
            beatboxerSelectedByCategory[category][beatboxerOneAddress] &&
                beatboxerSelectedByCategory[category][beatboxerTwoAddress],
            "BeatboxerNotSelected"
        );
        require(endTime > startTime, "EndTimeBeforeStartTime");

        if (category != metaData.competitionState) {
            metaData.competitionState = category;
        }

        uint256 battleId = battles.length;
        battles.push(
            Battle(
                battleId,
                BattleBeatboxer(ytVideoIdOne, beatboxerOneAddress, 0, 0),
                BattleBeatboxer(ytVideoIdTwo, beatboxerTwoAddress, 0, 0),
                address(0),
                startTime,
                endTime,
                winningAmount,
                category,
                name
            )
        );
        emit BattleCreated(battleId, name, category);
    }

    function voteBattle(
        uint256 battleId,
        Point calldata point1,
        Point calldata point2
    ) external isJudge {
        require(battleId < battles.length, "BattleNotFound");
        Battle storage battle = battles[battleId];
        require(battle.winnerAddress == address(0), "BattleAlreadyOver");
        require(
            battle.startTime <= block.timestamp &&
                battle.endTime >= block.timestamp,
            "BattleNotStartedOrOver"
        );
        require(judgeVoted[battleId][msg.sender] == false, "JudgeAlreadyVoted");
        battle.beatboxerOne.score += _calculateScore(point1);
        battle.beatboxerTwo.score += _calculateScore(point2);
        pointsByBattle[battleId].push(point1);
        pointsByBattle[battleId].push(point2);
        judgeVoted[battleId][msg.sender] = true;
        if (judgeCount.current() * 2 == pointsByBattle[battleId].length) {
            battleIdToUpkeepNeeded[battleId] = true;
        }
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

    function addJudge(address judgeAddress, string memory _name)
        external
        isAdminOrHelper
    {
        require(!hasRole(JUDGE_ROLE, judgeAddress), "JudgeAlreadyExists");
        _setupRole(JUDGE_ROLE, judgeAddress);
        judgeCount.increment();
        emit JudgeAdded(judgeAddress, _name);
    }

    function removeJudge(address judgeAddress) external isAdminOrHelper {
        require(hasRole(JUDGE_ROLE, judgeAddress), "JudgeNotFound");
        _revokeRole(JUDGE_ROLE, judgeAddress);
        judgeCount.decrement();
        emit JudgeRemoved(judgeAddress);
    }

    function addBeatboxers(
        address[] memory beatboxerAddresses,
        string[] memory names
    ) external isAdminOrHelper {
        require(beatboxerAddresses.length == names.length, "LengthMismatch");
        for (uint256 i = 0; i < beatboxerAddresses.length; i++) {
            if (
                beatboxerAddresses[i] != address(0) &&
                !beatboxerSelectedByCategory[CompetitionState.TOP16][
                    beatboxerAddresses[i]
                ]
            ) {
                beatboxerSelectedByCategory[CompetitionState.TOP16][
                    beatboxerAddresses[i]
                ] = true;
                beatboxerIndexByAddress[beatboxerAddresses[i]] = beatboxers
                    .length;
                beatboxers.push(Beatboxer(names[i], beatboxerAddresses[i], 0));
                emit BeatboxerAdded(beatboxerAddresses[i], names[i]);
            }
        }
    }

    function removeBeatboxer(address beatboxerAddress)
        external
        isAdminOrHelper
    {
        require(
            beatboxerSelectedByCategory[CompetitionState.TOP16][
                beatboxerAddress
            ],
            "BeatboxerNotFound"
        );
        delete beatboxerSelectedByCategory[CompetitionState.TOP16][
            beatboxerAddress
        ];
        uint256 index = beatboxerIndexByAddress[beatboxerAddress];
        uint256 lastIndex = beatboxers.length - 1;
        Beatboxer memory _beatboxer = beatboxers[lastIndex];
        beatboxers[index] = _beatboxer;
        beatboxerIndexByAddress[_beatboxer.beatboxerAddress] = index;
        delete beatboxers[lastIndex];
        delete beatboxerIndexByAddress[beatboxerAddress];
        emit BeatboxerRemoved(beatboxerAddress);
    }

    function setName(string memory name) external isAdmin {
        metaData.name = name;
    }

    function setDescription(string memory description) external isAdmin {
        metaData.description = description;
    }

    function setImage(string memory image) external isAdmin {
        metaData.image = image;
    }

    function startWildcard() external isAdmin {
        require(
            metaData.competitionState == CompetitionState.NOT_STARTED,
            "CompetitionAlreadyStarted"
        );
        metaData.competitionState = CompetitionState.WILDCARD;
    }

    function endWildcard() external isAdmin {
        require(
            metaData.competitionState == CompetitionState.WILDCARD,
            "CompetitionNotStarted"
        );
        metaData.competitionState = CompetitionState.TOP16;
    }

    function getAllBattles() external view returns (Battle[] memory) {
        return battles;
    }

    function getCurrentBeatboxers() external view returns (Beatboxer[] memory) {
        uint256 totalBeatboxers;
        uint256 counter;
        if (metaData.competitionState <= CompetitionState.TOP16) {
            return beatboxers;
        }
        if (metaData.competitionState == CompetitionState.TOP8) {
            totalBeatboxers = 8;
        } else if (metaData.competitionState == CompetitionState.SEMIFINAL) {
            totalBeatboxers = 4;
        } else {
            totalBeatboxers = 2;
        }
        Beatboxer[] memory _beatboxers = new Beatboxer[](totalBeatboxers);
        for (uint256 i; i < totalBeatboxers; i++) {
            if (
                beatboxerSelectedByCategory[metaData.competitionState][
                    beatboxers[i].beatboxerAddress
                ]
            ) {
                _beatboxers[counter] = beatboxers[i];
                counter++;
            }
        }
        return _beatboxers;
    }

    function getVotedBattlesIndices(address judge)
        external
        view
        returns (uint256[] memory)
    {
        if (!hasRole(JUDGE_ROLE, judge)) {
            return new uint256[](0);
        }
        uint256 indicesCount = 0;
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
        uint256 totalBattles = battles.length;
        upkeepNeeded = battleIdToUpkeepNeeded[
            totalBattles > 0 ? totalBattles - 1 : 0
        ];
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        uint256 battleId = battles.length - 1;
        if (battleIdToUpkeepNeeded[battleId]) {
            battleIdToUpkeepNeeded[battleId] = false;
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
        } else {
            battle.beatboxerTwo.score += 1;
        }
        if (battle.beatboxerOne.score > battle.beatboxerTwo.score) {
            beatboxers[
                beatboxerIndexByAddress[battle.beatboxerOne.beatboxerAddress]
            ].latestScore = battle.beatboxerOne.score;
            battle.beatboxerOne.likeCount = likeCount1;
            battle.winnerAddress = battle.beatboxerOne.beatboxerAddress;
            beatboxerSelectedByCategory[metaData.competitionState][
                battle.beatboxerOne.beatboxerAddress
            ] = true;
        } else {
            beatboxers[
                beatboxerIndexByAddress[battle.beatboxerTwo.beatboxerAddress]
            ].latestScore = battle.beatboxerTwo.score;
            battle.beatboxerTwo.likeCount = likeCount2;
            battle.winnerAddress = battle.beatboxerTwo.beatboxerAddress;
            beatboxerSelectedByCategory[metaData.competitionState][
                battle.beatboxerTwo.beatboxerAddress
            ] = true;
        }
        delete battleIdToUpkeepNeeded[battleId];
        emit WinnerSelected(battleId, battle.winnerAddress);
    }

    receive() external payable {
        // Do nothing
    }

    fallback() external payable {
        // Do nothing
    }
}
