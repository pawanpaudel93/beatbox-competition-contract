//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract BbxCompetition is AccessControl {
    using Counters for Counters.Counter;

    bytes32 public constant HELPER_ROLE = keccak256("HELPER_ROLE");
    bytes32 public constant JUDGE_ROLE = keccak256("JUDGE_ROLE");

    struct Beatboxer {
        string name;
        address beatboxerAddress;
        uint8 latestScore;
    }

    struct BattleBeatboxer {
        string videoUrl;
        address beatboxerAddress;
        uint8 score;
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
        // uint8 crowdVote;
    }

    struct Battle {
        uint256 id;
        BattleBeatboxer beatboxerOne;
        BattleBeatboxer beatboxerTwo;
        address winnerAddress;
        uint256 startTime;
        uint256 endTime;
        uint256 winningAmount;
        uint256 totalVotes;
        CompetitionState category;
        string name;
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

    struct MetaData {
        string name;
        string description;
        string image;
        CompetitionState competitionState;
    }

    MetaData public metaData;
    Battle[] public battles;
    Beatboxer[] public beatboxers;
    Counters.Counter public judgeCount;
    mapping(address => uint256) public beatboxerIndexByAddress;
    mapping(CompetitionState => mapping(address => bool))
        private beatboxerSelectedByCategory;
    mapping(uint256 => mapping(address => bool)) public judgeVoted;
    mapping(uint256 => Point[]) public pointsByBattle;

    event BattleCreated(
        address competitionAddress,
        uint256 id,
        string name,
        CompetitionState category,
        address beatboxerOneAddress,
        address beatboxerTwoAddress,
        uint256 startTime,
        uint256 endTime,
        uint256 winningAmount
    );

    event BeatboxerAdded(
        address competitionAddress,
        address beatboxerAddress,
        string name
    );
    event BeatboxerRemoved(
        address competitionAddress,
        address beatboxerAddress
    );
    event JudgeAdded(
        address competitionAddress,
        address judgeAddress,
        string name
    );
    event JudgeRemoved(address competitionAddress, address judgeAddress);

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
        string memory image
    ) {
        metaData = MetaData(
            name,
            description,
            image,
            CompetitionState.NOT_STARTED
        );
        _setupRole(DEFAULT_ADMIN_ROLE, contractOwner);
    }

    function startBattle(
        string memory name,
        CompetitionState category,
        address beatboxerOneAddress,
        address beatboxerTwoAddress,
        string memory videoUrlOne,
        string memory videoUrlTwo,
        uint256 startTime,
        uint256 endTime,
        uint256 winningAmount
    ) public isAdmin {
        require(
            metaData.competitionState > CompetitionState.WILDCARD,
            "Battle hasn't started yet"
        );
        require(
            beatboxerSelectedByCategory[category][beatboxerOneAddress] &&
                beatboxerSelectedByCategory[category][beatboxerTwoAddress],
            "Beatboxers are not selected for this battle"
        );
        require(endTime > startTime, "End time must be after start time");

        if (category != metaData.competitionState) {
            metaData.competitionState = category;
        }

        Battle memory battle;
        uint256 battleId = battles.length;
        battle.id = battleId;
        battle.name = name;
        battle.category = category;
        battle.beatboxerOne = BattleBeatboxer(
            videoUrlOne,
            beatboxerOneAddress,
            0
        );
        battle.beatboxerTwo = BattleBeatboxer(
            videoUrlTwo,
            beatboxerTwoAddress,
            0
        );
        battle.startTime = startTime;
        battle.endTime = endTime;
        battle.winningAmount = winningAmount;

        battles.push(battle);

        emit BattleCreated(
            address(this),
            battleId,
            name,
            category,
            beatboxerOneAddress,
            beatboxerTwoAddress,
            startTime,
            endTime,
            winningAmount
        );
    }

    function voteBattle(
        uint256 battleId,
        Point calldata point1,
        Point calldata point2
    ) public isJudge {
        require(battleId < battles.length, "Battle id out of range");
        Battle storage battle = battles[battleId];
        require(battle.winnerAddress == address(0), "Battle already finished");
        require(
            battle.startTime <= block.timestamp &&
                battle.endTime >= block.timestamp,
            "Battle has not started or has already ended"
        );
        require(
            judgeVoted[battleId][msg.sender] == false,
            "You have already voted for this battle"
        );
        battle.beatboxerOne.score += _calculateScore(point1);
        battle.beatboxerTwo.score += _calculateScore(point2);
        pointsByBattle[battleId].push(point1);
        pointsByBattle[battleId].push(point2);
        battle.totalVotes++;
        judgeVoted[battleId][msg.sender] = true;
        if (judgeCount.current() == battle.totalVotes) {
            // TODO: Calculate winner
            // after winning set beatboxerSelectedByCategory and also set last score of beatboxer
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
        public
        isAdminOrHelper
    {
        require(!hasRole(JUDGE_ROLE, judgeAddress), "Judge already exists");
        _setupRole(JUDGE_ROLE, judgeAddress);
        judgeCount.increment();
        emit JudgeAdded(address(this), judgeAddress, _name);
    }

    function removeJudge(address judgeAddress) public isAdminOrHelper {
        require(hasRole(JUDGE_ROLE, judgeAddress), "Judge does not exist");
        _revokeRole(JUDGE_ROLE, judgeAddress);
        judgeCount.decrement();
        emit JudgeRemoved(address(this), judgeAddress);
    }

    function addBeatboxer(address beatboxerAddress, string memory _name)
        public
        isAdminOrHelper
    {
        require(
            beatboxerAddress != address(0),
            "Beatboxer address cannot be 0"
        );
        require(
            !beatboxerSelectedByCategory[CompetitionState.TOP16][
                beatboxerAddress
            ],
            "Beatboxer already exists"
        );
        beatboxerSelectedByCategory[CompetitionState.TOP16][
            beatboxerAddress
        ] = true;
        beatboxerIndexByAddress[beatboxerAddress] = beatboxers.length;
        beatboxers.push(Beatboxer(_name, beatboxerAddress, 0));
        emit BeatboxerAdded(address(this), beatboxerAddress, _name);
    }

    function addBeatboxers(
        address[] memory beatboxerAddresses,
        string[] memory _names
    ) public isAdminOrHelper {
        require(
            beatboxerAddresses.length == _names.length,
            "Beatboxer addresses and names must be the same length"
        );
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
                beatboxers.push(Beatboxer(_names[i], beatboxerAddresses[i], 0));
                emit BeatboxerAdded(
                    address(this),
                    beatboxerAddresses[i],
                    _names[i]
                );
            }
        }
    }

    function removeBeatboxer(address beatboxerAddress) public isAdminOrHelper {
        require(
            beatboxerSelectedByCategory[CompetitionState.TOP16][
                beatboxerAddress
            ],
            "Beatboxer does not exist"
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
        emit BeatboxerRemoved(address(this), beatboxerAddress);
    }

    function setName(string memory _name) public isAdmin {
        metaData.name = _name;
    }

    function setDescription(string memory _description) public isAdmin {
        metaData.description = _description;
    }

    function setImage(string memory _image) public isAdmin {
        metaData.image = _image;
    }

    function startWildcard() external isAdmin {
        require(
            metaData.competitionState == CompetitionState.NOT_STARTED,
            "Competition has already started"
        );
        metaData.competitionState = CompetitionState.WILDCARD;
    }

    function endWildcard() external isAdmin {
        require(
            metaData.competitionState == CompetitionState.WILDCARD,
            "Competition has not started"
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

    receive() external payable {
        // Do nothing
    }

    fallback() external payable {
        // Do nothing
    }
}
