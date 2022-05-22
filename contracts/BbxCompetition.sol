//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "hardhat/console.sol";

contract BeatboxCompetition is
    AccessControl,
    ChainlinkClient,
    KeeperCompatibleInterface,
    VRFConsumerBaseV2
{
    using Counters for Counters.Counter;
    using Chainlink for Chainlink.Request;

    uint256 private constant ORACLE_PAYMENT =
        ((0 * LINK_DIVISIBILITY) / 100) * 5;
    bytes32 private immutable jobId;
    bytes32 private constant HELPER_ROLE = keccak256("HELPER_ROLE");
    bytes32 private constant JUDGE_ROLE = keccak256("JUDGE_ROLE");
    uint256 public constant BEATBOXERS_COUNT = 16;
    uint256 public constant MAX_JUDGES = 4;

    struct Beatboxer {
        string name;
        address beatboxerAddress;
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
        BattleBeatboxer beatboxerOne;
        BattleBeatboxer beatboxerTwo;
        address winnerAddress;
        uint256 startTime;
        uint256 endTime;
        uint256 winningAmount;
        CompetitionState state;
        string name;
    }

    struct BattleOpponent {
        uint256 beatboxerOneId;
        uint256 beatboxerTwoId;
        bool isCompleted;
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
    Beatboxer[] public beatboxers;
    Counters.Counter public judgeCount;
    bool private s_upkeepNeeded;

    // Chainlink VRF
    VRFCoordinatorV2Interface private COORDINATOR;
    uint64 private subscriptionId;
    bytes32 private keyHash;
    uint32 private callbackGasLimit = 100000;
    uint16 private requestConfirmations = 3;
    uint32 private numWords = 1;

    mapping(address => uint256) private beatboxerIndexByAddress;
    mapping(CompetitionState => uint256[]) competitionStateToBeatboxerIds;
    mapping(CompetitionState => uint256) public battleCountByState;
    mapping(uint256 => mapping(address => bool)) public judgeVoted;
    mapping(uint256 => Point[]) public pointsByBattle;
    mapping(CompetitionState => BattleOpponent[])
        public competitionStateToBattleOpponents;
    mapping(address => uint256) public balances;

    event BattleCreated(uint256 id, string name, CompetitionState state);
    event BeatboxersAdded();
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
        bytes32 name,
        address contractOwner,
        string memory description,
        string memory imageURI,
        address chainlinkToken,
        address chainlinkOracle,
        bytes32 chainlinkJobId,
        address vrfCoordinator
    ) VRFConsumerBaseV2(vrfCoordinator) {
        metaData = MetaData(
            name,
            imageURI,
            description,
            CompetitionState.NOT_STARTED
        );
        _setupRole(DEFAULT_ADMIN_ROLE, contractOwner);
        setChainlinkToken(chainlinkToken);
        setChainlinkOracle(chainlinkOracle);
        jobId = chainlinkJobId;
    }

    function startBattle(
        uint256 stateBattleId,
        string memory name,
        CompetitionState state,
        bytes11 ytVideoIdOne,
        bytes11 ytVideoIdTwo,
        uint256 startTime,
        uint256 endTime,
        uint256 winningAmount
    ) external isAdmin {
        require(metaData.competitionState == state, "CompetitionStateMismatch");
        BattleOpponent
            memory battleOpponent = competitionStateToBattleOpponents[
                metaData.competitionState
            ][stateBattleId];
        require(
            battleOpponent.beatboxerOneId != battleOpponent.beatboxerTwoId,
            "IdCannotBeSame"
        );
        require(!battleOpponent.isCompleted, "BattleAlreadyCompleted");
        require(endTime > startTime, "EndTimeBeforeStartTime");
        address beatboxerOneAddress = beatboxers[battleOpponent.beatboxerOneId]
            .beatboxerAddress;
        address beatboxerTwoAddress = beatboxers[battleOpponent.beatboxerTwoId]
            .beatboxerAddress;
        uint256 battleId = battles.length;
        battles.push(
            Battle(
                BattleBeatboxer(ytVideoIdOne, beatboxerOneAddress, 0, 0),
                BattleBeatboxer(ytVideoIdTwo, beatboxerTwoAddress, 0, 0),
                address(0),
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
            s_upkeepNeeded = true;
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
        require(
            metaData.competitionState <= CompetitionState.WILDCARD_SELECTION,
            "CompetitionStateMismatch"
        );
        require(judgeCount.current() <= MAX_JUDGES, "TooManyJudges");
        require(!hasRole(JUDGE_ROLE, judgeAddress), "JudgeAlreadyExists");
        _setupRole(JUDGE_ROLE, judgeAddress);
        judgeCount.increment();
        emit JudgeAdded(judgeAddress, _name);
    }

    function removeJudge(address judgeAddress) external isAdminOrHelper {
        require(
            metaData.competitionState <= CompetitionState.WILDCARD_SELECTION,
            "CompetitionStateMismatch"
        );
        require(hasRole(JUDGE_ROLE, judgeAddress), "JudgeNotFound");
        _revokeRole(JUDGE_ROLE, judgeAddress);
        judgeCount.decrement();
        emit JudgeRemoved(judgeAddress);
    }

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

    function removeBeatboxer(address beatboxerAddress)
        external
        isAdminOrHelper
    {
        require(
            metaData.competitionState == CompetitionState.WILDCARD_SELECTION,
            "CompetitionStateMismatch"
        );
        require(
            beatboxers[beatboxerIndexByAddress[beatboxerAddress]]
                .beatboxerAddress == beatboxerAddress,
            "BeatboxerNotFound"
        );
        uint256 index = beatboxerIndexByAddress[beatboxerAddress];
        uint256 lastIndex = beatboxers.length - 1;
        Beatboxer memory _beatboxer = beatboxers[lastIndex];
        beatboxers[index] = _beatboxer;
        beatboxerIndexByAddress[_beatboxer.beatboxerAddress] = index;
        delete beatboxers[lastIndex];
        delete beatboxerIndexByAddress[beatboxerAddress];
        emit BeatboxerRemoved(beatboxerAddress);
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

    function setSubscriptionId(uint64 _subscriptionId) external isAdmin {
        subscriptionId = _subscriptionId;
    }

    function startWildcard() external isAdmin {
        require(
            metaData.competitionState == CompetitionState.NOT_STARTED,
            "CompetitionAlreadyStarted"
        );
        metaData.competitionState = CompetitionState.WILDCARD_SUBMISSION;
    }

    function endWildcard() external isAdmin {
        require(
            metaData.competitionState == CompetitionState.WILDCARD_SUBMISSION,
            "CompetitionNotStarted"
        );
        metaData.competitionState = CompetitionState.WILDCARD_SELECTION;
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

    function winnerWithdraw(uint256 amount) external {
        require(
            address(this).balance >= amount,
            "InsufficientCompetitionBalance"
        );
        require(balances[msg.sender] >= amount, "InsufficientWinnerBalance");
        balances[msg.sender] -= amount;
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "FailedToSend");
    }

    function withdraw(uint256 amount) external isAdmin {
        require(address(this).balance >= amount, "InsufficientBalance");
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "FailedToSend");
    }

    function getAllBattles() external view returns (Battle[] memory) {
        return battles;
    }

    function getCurrentBattles() external view returns (Beatboxer[2][] memory) {
        BattleOpponent[]
            memory battleOpponents = competitionStateToBattleOpponents[
                metaData.competitionState
            ];
        Beatboxer[2][] memory _beatboxers = new Beatboxer[2][](
            battleOpponents.length
        );
        for (uint256 i; i < battleOpponents.length; i++) {
            _beatboxers[i][0] = beatboxers[battleOpponents[i].beatboxerOneId];
            _beatboxers[i][1] = beatboxers[battleOpponents[i].beatboxerTwoId];
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

    receive() external payable {
        // Do nothing
    }

    fallback() external payable {
        // Do nothing
    }
}
