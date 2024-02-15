// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IOrcNation.sol";
import "forge-std/console.sol";

contract TestingEnvLib is Script {
    IOrcNation public nft;

    function _setUp(string memory _chain) internal {
        string memory file = vm.readFile("./json_out/deployedAddresses.json");
        bool exists = vm.keyExists(file, _chain);
        require(exists, "no records found");
        string memory key = string.concat(_chain, ".OrcNation");
        address orcNationAddress = vm.parseJsonAddress(file, key);
        nft = IOrcNation(orcNationAddress);
    }

    function _mintTokens(uint256 _numTokens, uint256[] memory _pks) internal {
        console.log("minting %s tokens....", _numTokens);
        uint256 targetTokenId = nft.getCurrentTokenId() + _numTokens;
        uint256 pkIndex;
        while(nft.getCurrentTokenId() < targetTokenId) {
            uint256 value = nft.calculatePrice(1);
            vm.startBroadcast(_pks[pkIndex]);
            nft.mint{value: value}(vm.addr(_pks[pkIndex]), 1);
            vm.stopBroadcast();
            ++pkIndex;
            if(pkIndex >= _pks.length) pkIndex = 0;
        }
        console.log("minting complete");
        console.log("total supply: ", nft.getCurrentTokenId());
    }
}

contract TestingEnvLocal is TestingEnvLib {
    // define the contract & get address
    string public chain = ".anvil";

    uint256[] public anvilBuyerPks = [
        vm.envUint("ANVIL_PK_3"),
        vm.envUint("ANVIL_PK_4"),
        vm.envUint("ANVIL_PK_5"),
        vm.envUint("ANVIL_PK_6"),
        vm.envUint("ANVIL_PK_7"),
        vm.envUint("ANVIL_PK_8"),
        vm.envUint("ANVIL_PK_9")
    ];

    function setUp() public {
        _setUp(chain);
    }

    function mintTokens(uint256 _numTokens) public {
        // warp to mint
        _mintTokens(_numTokens, anvilBuyerPks);
    }

    


    // define list of pks
        // loop through - get price, purchase
}