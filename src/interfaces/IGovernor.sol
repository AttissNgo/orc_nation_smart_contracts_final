// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IGovernor {
    function isAdmin(address) external view returns (bool);
    function proposeTransaction(address _to, uint256 _value, bytes calldata _data) external returns (uint256);
    function signTransaction(uint256 _txIndex) external;
}