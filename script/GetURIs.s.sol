// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IOrcNation.sol";
import "forge-std/console.sol";

contract GetURIsMumbai is Script {

    string public chain = ".mumbai";
    IOrcNation public nft;

    function setUp() public {}

    function run() public {
        string memory file = vm.readFile("./json_out/deployedAddresses.json");
        bool exists = vm.keyExists(file, chain);
        require(exists, "no records found");
        string memory key = string.concat(chain, ".OrcNation");
        address orcNationAddress = vm.parseJsonAddress(file, key);
        nft = IOrcNation(orcNationAddress);

        uint256 numTokens = nft.getCurrentTokenId();
        console.log("Total tokens minted: ", numTokens);
        for(uint i = 1; i <= numTokens; ++i) {
            uint256 uriExt = nft.tokenIdToUriExtension(i);
            console.log("token id %s : %s", i, uriExt);
            if(uriExt == nft.tokenIdToUriExtension(i - 1)) {
                console.log("++++++++++++++++++++++++++++");
                console.log("+++++SEQUENCE+++++FOUND+++++");
                console.log("++++++++++++++++++++++++++++");
            }
            // console.log(i);
        }

        // uint256 ownerPrivateKey = vm.envUint("MUMBAI_PK_1");
        // address owner = IOrcNation(orcNation).OWNER();
        // vm.startBroadcast(ownerPrivateKey);


    }
}