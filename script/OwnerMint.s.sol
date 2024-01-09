// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IOrcNation.sol";
import "forge-std/console.sol";

contract OwnerMint is Script {

    function setUp() public {}

    // function run() public {
    //     // get proper deployed address and instantiate IOrcNation
    //     console.log(_message);
    // }

    function mint(string memory _chain) public {
        string memory file = vm.readFile("./json_out/deployedAddresses.json");
        bool exists = vm.keyExists(file, string.concat(".", _chain));
        require(exists, "no records found");
        string memory key = string.concat(".", _chain, ".OrcNation");
        address orcNation = vm.parseJsonAddress(file, key);
        // uint256 test = IOrcNation(orcNation).getCurrentTokenId();
        // console.log(test);
        uint16 numMinted = IOrcNation(orcNation).ownerMintCounter();
        uint16 maxOwnerMints = IOrcNation(orcNation).MAX_OWNER_MINTS();
        console.log(maxOwnerMints);
    }

    function testMsg(string memory _message) public {
        console.log(_message);
    } // to run with args forge script script/OwnerMint.s.sol:OwnerMint --sig "testMsg(string)" "someMessage"
}