// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/interfaces/IOrcNation.sol";
import "../src/interfaces/IGovernor.sol";
import "../src/interfaces/IPaymentSplitter.sol";

contract TestingEnvLib is Script {
    IOrcNation public nft;
    IGovernor public governor;
    IPaymentSplitter public paymentSplitter;

    function _setUp(string memory _chain) internal {
        string memory file = vm.readFile("./json_out/deployedAddresses.json");
        bool exists = vm.keyExists(file, _chain);
        require(exists, "no records found");

        string memory key = string.concat(_chain, ".OrcNation");
        address orcNationAddress = vm.parseJsonAddress(file, key);
        nft = IOrcNation(orcNationAddress);

        key = string.concat(_chain, ".Governor");
        address governorAddress = vm.parseJsonAddress(file, key);
        governor = IGovernor(governorAddress);

        key = string.concat(_chain, ".PaymentSplitter");
        address paymentSplitterAddress = vm.parseJsonAddress(file, key);
        paymentSplitter = IPaymentSplitter(paymentSplitterAddress);

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

    uint256[] public anvilAdmins = [
        vm.envUint("ANVIL_PK_0"),
        vm.envUint("ANVIL_PK_1"),
        vm.envUint("ANVIL_PK_2")
    ];

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

    function createDummyGovernorProposals() public {
        bytes memory data = abi.encodeWithSignature("setTokenPrice(uint256)", 40);
        uint256 txIndex;
        vm.startBroadcast(anvilAdmins[0]);
        txIndex = governor.proposeTransaction(address(nft), 0, data);
        vm.stopBroadcast();

        data = abi.encodeWithSignature("addAdmin(address)", vm.addr(anvilBuyerPks[0]));
        vm.startBroadcast(anvilAdmins[1]);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.stopBroadcast();

        data = abi.encodeWithSignature("claimCompanyShare(address)", vm.addr(anvilAdmins[2]));
        vm.startBroadcast(anvilAdmins[2]);
        txIndex = governor.proposeTransaction(address(paymentSplitter), 0, data);
        vm.stopBroadcast();

        data = abi.encodeWithSignature("setTokenPrice(uint256)", 55);
        txIndex;
        vm.startBroadcast(anvilAdmins[0]);
        txIndex = governor.proposeTransaction(address(nft), 0, data);
        vm.stopBroadcast();

        data = abi.encodeWithSignature("removeAdmin(address)", vm.addr(anvilBuyerPks[0]));
        vm.startBroadcast(anvilAdmins[1]);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.stopBroadcast();
    }


    // define list of pks
        // loop through - get price, purchase
}