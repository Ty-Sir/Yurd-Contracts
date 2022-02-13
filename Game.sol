// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "../node_modules/@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "../node_modules/@openzeppelin/contracts/utils/Address.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./QuickSort.sol";

contract Game is VRFConsumerBase, Ownable, ReentrancyGuard {
    using Address for address payable;
    using QuickSort for uint256[];

    bytes32 internal keyHash;

    address private dev;

    uint256 internal fee;

    uint256 private currentJackpot;

    uint256 private highestScore;

    address private currentWinner;

    uint256 private gamesTillJackpot;

    uint256 private gamesPlayedInRound;

    uint256 private priceToPlay;

    uint256 private round;

    struct Scoring {
        uint256 credit;
        uint256 canRoll;
        uint256[2] ones;
        uint256[2] twos;
        uint256[2] threes;
        uint256[2] fours;
        uint256[2] fives;
        uint256[2] sixes;
        uint256[2] pair;
        uint256[2] threeKind;
        uint256[2] fiveKind;
        uint256[2] threeRow;
        uint256[2] fourRow;
        uint256[2] hogwash;
        uint256 upperScore;
        uint256 lowerScore;
    }

    mapping(address => uint256) private winnersJackpots;

    mapping(bytes32 => address) private requestIdToAddress;

    mapping(address => uint256[]) private dice;

    mapping(address => bool) private vrf;

    mapping(address => Scoring) private game;

    event GameStarted(address player);
    event GameFinished(address player, uint256 score, uint256 round);
    event JackpotWon(address winner, uint256 jackpotAmount, uint256 round);

    constructor(address _dev)
        VRFConsumerBase(
            0x8C7382F9D8f56b33781fE506E897a4F1e2d17255,
            0x326C977E6efc84E512bB9C30f76E30c160eD06FB
        )
    {
        setDevAddress(_dev);
        keyHash = 0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4;
        fee = 0.0001 * 10**18;
        priceToPlay = 100000000 gwei; //.1 matic
        round = 1;
        gamesTillJackpot = 5;
    }

    function setPriceToPlay(uint256 _newPrice) public onlyOwner {
        priceToPlay = _newPrice;
    }

    function setRoundLength(uint256 _gamesTillJackpot) public onlyOwner {
        gamesTillJackpot = _gamesTillJackpot;
    }

    function setKeyHash(bytes32 _keyHash) public onlyOwner {
        keyHash = _keyHash;
    }

    function setDevAddress(address _dev) public onlyOwner {
        dev = _dev;
    }

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    function getVars()
        public
        view
        returns (
            address,
            uint256,
            uint256,
            uint256
        )
    {
        return (currentWinner, currentJackpot, highestScore, round);
    }

    function getJackpotAmount() public view returns (uint256) {
        return winnersJackpots[msg.sender];
    }

    function getGame() public view returns (Scoring memory scoring) {
        return game[msg.sender];
    }

    function getVRF() public view returns (bool) {
        return vrf[msg.sender];
    }

    function sendPaymentToPlay() public payable nonReentrant {
        require(game[msg.sender].credit == 0);
        require(msg.value == priceToPlay);
        currentJackpot += (msg.value / 4) * 3;
        payable(dev).sendValue((msg.value / 4));
        game[msg.sender].credit = 1;
        emit GameStarted(msg.sender);
    }

    function gameOver() public nonReentrant {
        require(game[msg.sender].credit == 1);
        if (game[msg.sender].upperScore >= 42000) {
            game[msg.sender].upperScore += 23000;
        }
        uint256 _currentRound = round;
        uint256 _score = game[msg.sender].upperScore +
            game[msg.sender].lowerScore;

        delete game[msg.sender];
        delete dice[msg.sender];
        delete vrf[msg.sender];
        gamesPlayedInRound += 1;

        if (_score > highestScore) {
            highestScore = _score;
            currentWinner = msg.sender;
        }
        if (gamesTillJackpot - gamesPlayedInRound == 0) {
            _sendWinningsToMapping();
        }
        emit GameFinished(msg.sender, _score, _currentRound);
    }

    function _sendWinningsToMapping() internal {
        uint256 jackpot = currentJackpot;
        uint256 winningRound = round;
        address jackpotWinner = currentWinner;

        round += 1;
        currentJackpot = 0;
        currentWinner = 0x0000000000000000000000000000000000000000;
        highestScore = 0;
        gamesPlayedInRound = 0;

        winnersJackpots[jackpotWinner] += jackpot;

        emit JackpotWon(jackpotWinner, jackpot, winningRound);
    }

    function withdrawWinnings() public {
        require(winnersJackpots[msg.sender] != 0);
        uint256 payment = winnersJackpots[msg.sender];

        winnersJackpots[msg.sender] = 0;
        delete winnersJackpots[msg.sender];

        payable(msg.sender).sendValue(payment);
    }

    function rollDice() public returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee);
        require(game[msg.sender].credit == 1);
        require(game[msg.sender].canRoll == 0);
        require(vrf[msg.sender] == false);
        requestId = requestRandomness(keyHash, fee);
        requestIdToAddress[requestId] = msg.sender;
        vrf[msg.sender] = true;
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        address requestAddress = requestIdToAddress[requestId];
        _expand(randomness, requestAddress);
        game[requestAddress].canRoll = 1;
        delete requestIdToAddress[requestId];
    }

    function _expand(uint256 randomValue, address calledBy) internal {
        delete dice[calledBy];
        uint256[] memory expandedValues = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            expandedValues[i] =
                (uint256(keccak256(abi.encode(randomValue, i))) % 6) +
                1;
        }
        dice[calledBy] = QuickSort._sort(expandedValues);
        delete vrf[calledBy];
    }

    function getDice() public view returns (uint256[] memory) {
        return dice[msg.sender];
    }

    function scoreOnes() public {
        require(game[msg.sender].ones[1] == 0 && game[msg.sender].canRoll == 1);
        uint256[] memory _dice = dice[msg.sender];
        uint256 _score;
        for (uint256 i = 0; i < _dice.length; i++) {
            if (_dice[i] == 1) {
                _score++;
            }
        }
        game[msg.sender].upperScore += _score * 1000;
        game[msg.sender].ones[0] = _score * 1000;
        game[msg.sender].ones[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function scoreTwos() public {
        require(game[msg.sender].twos[1] == 0 && game[msg.sender].canRoll == 1);
        uint256[] memory _dice = dice[msg.sender];
        uint256 _score;
        for (uint256 i = 0; i < _dice.length; i++) {
            if (_dice[i] == 2) {
                _score += 2;
            }
        }
        game[msg.sender].upperScore += _score * 1000;
        game[msg.sender].twos[0] = _score * 1000;
        game[msg.sender].twos[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function scoreThrees() public {
        require(
            game[msg.sender].threes[1] == 0 && game[msg.sender].canRoll == 1
        );
        uint256[] memory _dice = dice[msg.sender];
        uint256 _score;
        for (uint256 i = 0; i < _dice.length; i++) {
            if (_dice[i] == 3) {
                _score += 3;
            }
        }
        game[msg.sender].upperScore += _score * 1000;
        game[msg.sender].threes[0] = _score * 1000;
        game[msg.sender].threes[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function scoreFours() public {
        require(
            game[msg.sender].fours[1] == 0 && game[msg.sender].canRoll == 1
        );
        uint256[] memory _dice = dice[msg.sender];
        uint256 _score;
        for (uint256 i = 0; i < _dice.length; i++) {
            if (_dice[i] == 4) {
                _score += 4;
            }
        }
        game[msg.sender].upperScore += _score * 1000;
        game[msg.sender].fours[0] = _score * 1000;
        game[msg.sender].fours[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function scoreFives() public {
        require(
            game[msg.sender].fives[1] == 0 && game[msg.sender].canRoll == 1
        );
        uint256[] memory _dice = dice[msg.sender];
        uint256 _score;
        for (uint256 i = 0; i < _dice.length; i++) {
            if (_dice[i] == 5) {
                _score += 5;
            }
        }
        game[msg.sender].upperScore += _score * 1000;
        game[msg.sender].fives[0] = _score * 1000;
        game[msg.sender].fives[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function scoreSixes() public {
        require(
            game[msg.sender].sixes[1] == 0 && game[msg.sender].canRoll == 1
        );
        uint256[] memory _dice = dice[msg.sender];
        uint256 _score;
        for (uint256 i = 0; i < _dice.length; i++) {
            if (_dice[i] == 6) {
                _score += 6;
            }
        }
        game[msg.sender].upperScore += _score * 1000;
        game[msg.sender].sixes[0] = _score * 1000;
        game[msg.sender].sixes[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function scoreHogwash() public {
        require(
            game[msg.sender].hogwash[1] == 0 && game[msg.sender].canRoll == 1
        );
        uint256[] memory _dice = dice[msg.sender];
        uint256 _score;
        for (uint256 i = 0; i < _dice.length; i++) {
            _score += _dice[i];
        }
        game[msg.sender].lowerScore += _score * 1000;
        game[msg.sender].hogwash[0] = _score * 1000;
        game[msg.sender].hogwash[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function scorePair() public {
        require(game[msg.sender].pair[1] == 0 && game[msg.sender].canRoll == 1);
        uint256[] memory _dice = dice[msg.sender];
        uint256 occurances = 1;
        uint256 _score;
        for (uint256 i = 0; i < _dice.length - 1; i++) {
            if (_dice[i + 1] == _dice[i]) {
                occurances++;
            }
        }
        if (occurances >= 2) {
            for (uint256 i = 0; i < _dice.length; i++) {
                _score += _dice[i];
            }
        }
        game[msg.sender].lowerScore += _score * 1000;
        game[msg.sender].pair[0] = _score * 1000;
        game[msg.sender].pair[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function scoreThreeOfAKind() public {
        require(
            game[msg.sender].threeKind[1] == 0 && game[msg.sender].canRoll == 1
        );
        uint256[] memory _dice = dice[msg.sender];
        uint256 occurances = 1;
        uint256 _score;
        for (uint256 i = 0; i < _dice.length - 2; i++) {
            if (_dice[i + 1] == _dice[i]) {
                if (_dice[i + 2] == _dice[i + 1]) {
                    occurances++;
                }
            }
        }
        if (occurances >= 2) {
            for (uint256 i = 0; i < _dice.length; i++) {
                _score += _dice[i];
            }
        }
        game[msg.sender].lowerScore += _score * 1000;
        game[msg.sender].threeKind[0] = _score * 1000;
        game[msg.sender].threeKind[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function scoreFiveOfAKind() public {
        require(
            game[msg.sender].fiveKind[1] == 0 && game[msg.sender].canRoll == 1
        );
        uint256[] memory _dice = dice[msg.sender];
        uint256 occurances = 1;
        for (uint256 i = 0; i < _dice.length - 1; i++) {
            if (_dice[i + 1] == _dice[i]) {
                occurances++;
            }
        }
        if (occurances == 5) {
            game[msg.sender].lowerScore += 50000;
            game[msg.sender].fiveKind[0] = 50000;
        } else {
            game[msg.sender].lowerScore += 0;
            game[msg.sender].fiveKind[0] = 0;
        }
        game[msg.sender].fiveKind[1] = 1;
        game[msg.sender].canRoll = 0;
    }

    function scoreThreeInARow() public {
        require(
            game[msg.sender].threeRow[1] == 0 && game[msg.sender].canRoll == 1
        );
        uint256[] memory _dice = dice[msg.sender];
        uint256 occurances = 1;
        for (uint256 i = 0; i < _dice.length - 1; i++) {
            if (_dice[i + 1] == _dice[i] + 1) {
                occurances++;
            }
        }
        if (occurances >= 3) {
            game[msg.sender].lowerScore += 30000;
            game[msg.sender].threeRow[0] = 30000;
        } else {
            game[msg.sender].lowerScore += 0;
            game[msg.sender].threeRow[0] = 0;
        }
        game[msg.sender].threeRow[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function scoreFourInARow() public {
        require(
            game[msg.sender].fourRow[1] == 0 && game[msg.sender].canRoll == 1
        );
        uint256[] memory _dice = dice[msg.sender];
        uint256 occurances = 1;
        for (uint256 i = 0; i < _dice.length - 1; i++) {
            if (_dice[i + 1] == _dice[i] + 1) {
                occurances++;
            }
        }
        if (occurances >= 4) {
            game[msg.sender].lowerScore += 40000;
            game[msg.sender].fourRow[0] = 40000;
        } else {
            game[msg.sender].lowerScore += 0;
            game[msg.sender].fourRow[0] = 0;
        }
        game[msg.sender].fourRow[1] = 1;
        game[msg.sender].canRoll = 0;
        _fiveOfKindBonusCheck(_dice, msg.sender);
    }

    function _fiveOfKindBonusCheck(uint256[] memory _diceArr, address _caller)
        internal
    {
        if (game[_caller].fiveKind[0] == 50000) {
            uint256 occurances = 1;
            for (uint256 i = 0; i < _diceArr.length - 1; i++) {
                if (_diceArr[i + 1] == _diceArr[i]) {
                    occurances++;
                }
            }
            if (occurances == 5) {
                game[_caller].lowerScore += 100000;
            }
        }
    }

    function withdrawLINK() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(
            0x326C977E6efc84E512bB9C30f76E30c160eD06FB
        );
        require(link.transfer(msg.sender, link.balanceOf(address(this))));
    }
}
