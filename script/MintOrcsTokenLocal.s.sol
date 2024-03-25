// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IGovernor.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MintOrcsTokenLocal is Script {
    IGovernor public governor;
    bytes public data;
    // address public tokenAddress;
    IERC20 public token;

    address[] public recipients = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // anvil 0
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // anvil 1
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC // anvil 2
    ];

    uint256[] public amounts = [
        1 ether,
        2 ether,
        3.3 ether
    ];

    function setUp() public {
        string memory file = vm.readFile("./json_out/deployedAddresses.json");
        bool exists = vm.keyExists(file, ".anvil");
        require(exists, "no records found");

        string memory key = string.concat(".anvil", ".Governor");
        address governorAddress = vm.parseJsonAddress(file, key);
        governor = IGovernor(governorAddress);

        key = string.concat(".anvil", ".OrcsToken");
        address tokenAddress = vm.parseJsonAddress(file, key);
        token = IERC20(tokenAddress);

        data = abi.encodeWithSignature("batchTransfer(address[],uint256[])", recipients, amounts);
    }

    // propose transaction and execute
    function run() public {
        // console.log(tokenAddress);
        // console.log(data);
        vm.startBroadcast(vm.envUint("ANVIL_PK_0"));
        uint256 txIndex = governor.proposeTransaction(address(token), 0, data);
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("ANVIL_PK_1"));
        governor.signTransaction(txIndex);
        vm.stopBroadcast();

        console.log("token balances after batch transfer:");
        console.log(token.balanceOf(recipients[0]));
        console.log(token.balanceOf(recipients[1]));
        console.log(token.balanceOf(recipients[2]));
    }
}