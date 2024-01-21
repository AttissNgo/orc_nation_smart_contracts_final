// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IOrcNation.sol";
import "forge-std/console.sol";

contract MintMumbai is Script {

    string public chain = ".mumbai";
    IOrcNation public nft;

    uint256[] private pks = [
        vm.envUint("MUMBAI_MINTER_PK_0"),
        vm.envUint("MUMBAI_MINTER_PK_1"),
        vm.envUint("MUMBAI_MINTER_PK_2")
    ];

    uint256 numTokensToMint = 10;

    function setUp() public {}

    function run() public {
        string memory file = vm.readFile("./json_out/deployedAddresses.json");
        bool exists = vm.keyExists(file, chain);
        require(exists, "no records found");
        string memory key = string.concat(chain, ".OrcNation");
        address orcNationAddress = vm.parseJsonAddress(file, key);
        nft = IOrcNation(orcNationAddress);

        console.log("minting nfts...");
        _mint10Each();
        _mint10Each();
        _mint10Each();

        uint256 numTokens = nft.getCurrentTokenId();
        console.log("Total tokens minted: ", numTokens);
    }

    function _mint10Each() internal {
        for(uint i; i < pks.length; ++i) {
            uint256 value = nft.calculatePrice(numTokensToMint);
            vm.startBroadcast(pks[i]);
            nft.mint{value: value}(vm.addr(pks[i]), 10);
            vm.stopBroadcast();
        }
    }
}