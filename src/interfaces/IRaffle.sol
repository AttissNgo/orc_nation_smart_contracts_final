// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IRaffle {
    function raffleDrawn(uint256) external returns (bool);
    function drawRaffle(uint256 _tokenThreshold) external;
    function raffleComplete(uint256 _tokenThreshold) external returns (bool);
    function receiveRafflePrize(uint256 _tokenThreshold, uint256[] memory _prizes) external payable;
    function getRaffleWinners(uint256 _tokenThreshold) external view returns (address[] memory); 
}

