//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol"; // AccessControl vs Ownable # TODO
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract BbxCompetition is AccessControl {
    using Counters for Counters.Counter;

    bytes32 public constant HELPER_ROLE = keccak256("HELPER_ROLE");
    bytes32 public constant JUDGE_ROLE = keccak256("JUDGE_ROLE");

    string public name;
    address public winner;

    struct Beatboxer {
        string name;
        address beatboxerAddress;
        bool added;
    }

    // struct Judge {
    //     string name;
    //     address judgeAddress;
    // }

    struct Battle {
        uint256 id;
        address beatboxerOneAddress;
        address beatboxerTwoAddress;
        address winnerAddress;
        uint256 beatboxerOneScore;
        uint256 beatboxerTwoScore;
        uint256 startTime;
        uint256 endTime;
        uint256 winningAmount;
        string name;
    }

    struct Point {
        uint256 originality;
        uint256 pitchAndTiming;
        uint256 complexity;
        uint256 enjoymentOfListening;
        uint256 video;
        uint256 audio;
        uint256 battle;
        uint256 extraPoint;
        // uint256 crowdVote;
    }

    Battle[] public battles;
    // Judge[] public judges;
    mapping(address => Beatboxer) public beatboxerByAddress;
    mapping(uint256 => mapping(address => Point)) public battlePoints;
    mapping(uint256 => mapping(address => bool)) public judgeVoted;
    Counters.Counter public beatboxerCount;

    event BattleCreated(
        uint256 id,
        string name,
        address beatboxerOneAddress,
        address beatboxerTwoAddress,
        uint256 startTime,
        uint256 endTime,
        uint256 winningAmount
    );

    event BeatboxerAdded(address beatboxerAddress, string name);
    event JudgeAdded(address judgeAddress, string name);

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

    constructor(string memory _name, address contractOwner) {
        name = _name;
        _setupRole(DEFAULT_ADMIN_ROLE, contractOwner);
    }

    function startBattle(
        string memory _name,
        address _beatboxerOneAddress,
        address _beatboxerTwoAddress,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _winningAmount
    ) public isAdmin {
        require(
            _beatboxerOneAddress != address(0) &&
                _beatboxerTwoAddress != address(0),
            "Beatboxer addresses cannot be 0"
        );
        require(
            _beatboxerOneAddress != _beatboxerTwoAddress,
            "Beatboxer addresses cannot be the same"
        );
        require(_endTime > _startTime, "End time must be after start time");

        Battle memory battle;
        battle.id = battles.length;
        battle.name = _name;
        battle.beatboxerOneAddress = _beatboxerOneAddress;
        battle.beatboxerTwoAddress = _beatboxerTwoAddress;
        battle.startTime = _startTime;
        battle.endTime = _endTime;
        battle.winningAmount = _winningAmount;

        battles.push(battle);

        emit BattleCreated(
            battle.id,
            battle.name,
            battle.beatboxerOneAddress,
            battle.beatboxerTwoAddress,
            battle.startTime,
            battle.endTime,
            battle.winningAmount
        );
    }

    function voteBattle(
        uint256 battleId,
        Point memory point1,
        Point memory point2
    ) public isJudge {
        require(battleId < battles.length, "Battle id out of range");
        Battle storage battle = battles[battleId];
        require(battle.winnerAddress != address(0), "Battle already finished");
        require(
            battle.startTime <= block.timestamp &&
                battle.endTime >= block.timestamp,
            "Battle has not started or has already ended"
        );
        require(
            judgeVoted[battleId][msg.sender] == false,
            "You have already voted for this battle"
        );
        battlePoints[battleId][battle.beatboxerOneAddress] = point1;
        battlePoints[battleId][battle.beatboxerTwoAddress] = point2;
        battle.beatboxerOneScore += _calculateScore(point1);
        battle.beatboxerTwoScore += _calculateScore(point2);
        judgeVoted[battleId][msg.sender] = true;
    }

    function _calculateScore(Point memory point)
        private
        pure
        returns (uint256)
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
        if (!hasRole(JUDGE_ROLE, judgeAddress)) {
            // judges.push(Judge(_name, judgeAddress));
            _setupRole(JUDGE_ROLE, judgeAddress);
            emit JudgeAdded(judgeAddress, _name);
        }
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
            beatboxerByAddress[beatboxerAddress].added == false,
            "Beatboxer already exists"
        );
        beatboxerByAddress[beatboxerAddress] = Beatboxer(
            _name,
            beatboxerAddress,
            true
        );
        beatboxerCount.increment();
        emit BeatboxerAdded(beatboxerAddress, _name);
    }

    function setName(string memory _name) public isAdmin {
        name = _name;
    }

    receive() external payable {
        // Do nothing
    }

    fallback() external payable {
        // Do nothing
    }
}
