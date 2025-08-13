// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract PokerEscrow {
    address public player1;
    address public player2;
    uint256 public betAmount;
    bool public gameStarted;
    address public winner;

    constructor(address _player2) payable {
        require(msg.value > 0, "Must send ETH to start");
        player1 = msg.sender;
        player2 = _player2;
        betAmount = msg.value;
        gameStarted = false;
    }

    function joinGame() external payable {
        require(msg.sender == player2, "Only Player 2 can join");
        require(msg.value == betAmount, "Bet must match Player 1's");
        gameStarted = true;
    }

    function declareWinner(address _winner) external {
        require(gameStarted, "Game not started");
        require(msg.sender == player1 || msg.sender == player2, "Only players can declare");
        winner = _winner;
        payable(winner).transfer(address(this).balance);
        gameStarted = false;
    }
}
