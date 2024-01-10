// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IOrcNation {
    function getCurrentTokenId() external view returns (uint256);
    function totalNumberOfBuyers() external view returns (uint256);
    function getBuyerByIndex(uint256 index) external view returns (address);
    function tokenIdToUriExtension(uint256) external view returns (uint256);
    function addRaffle2000Winners(address[] calldata _winners) external;
    function calculatePrice(uint256 _numberOfTokens) external view returns (uint256);
    function mint(uint256 _numberOfTokens) external payable returns (uint256); 
    function ownerMint(uint256 _numberOfTokens) external returns (uint256 requestId);
    function mintComp() external returns (uint256);
    function ownerMintCounter() external returns (uint16);
    function MAX_OWNER_MINTS() external returns (uint16);
    function OWNER() external returns (address);
    function balanceOf(address) external returns (uint256);
}