// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract PriceFeedMock {
    
    uint8 public decimals = 8;

    int256 public s_answer = 96054224;

    function setAnswer(int256 _answer) public {
        s_answer = _answer;
    }

    function latestRoundData() external view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) 
    {
        return(1, s_answer, 1, 1, 1);
    }
}