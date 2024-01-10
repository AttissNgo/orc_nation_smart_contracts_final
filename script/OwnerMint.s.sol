// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IOrcNation.sol";
import "forge-std/console.sol";

contract OwnerMint is Script {

    function setUp() public {}

    function mint(string memory _chain) public {
        string memory file = vm.readFile("./json_out/deployedAddresses.json");
        bool exists = vm.keyExists(file, string.concat(".", _chain));
        require(exists, "no records found");
        string memory key = string.concat(".", _chain, ".OrcNation");
        address orcNation = vm.parseJsonAddress(file, key);
 
        uint256 ownerPrivateKey = vm.envUint("MUMBAI_PK_1");
        address owner = IOrcNation(orcNation).OWNER();
        console.log("attempting 50 owner mints...");
        for(uint i; i < 5; ++i) {
            vm.startBroadcast(ownerPrivateKey);
            IOrcNation(orcNation).ownerMint(10);
            vm.stopBroadcast();
        }
        console.log("tokens minted");
        uint256 ownerBalance = IOrcNation(orcNation).balanceOf(owner);
        console.log("current owner balance: %s tokens", ownerBalance);

    }

}