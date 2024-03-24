// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {OrcsToken} from "../src/OrcsToken.sol";

contract DeployOrcsTokenMumbai is Script {

    address mumbaiGovernor = 0xD07aBdB65887034A3A05C57Df0D19A04C41FAe25;
    OrcsToken public token;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("POLYGON_PK_0"); // same on Mumbai
        vm.startBroadcast(deployerPrivateKey);
        token = new OrcsToken(mumbaiGovernor);
        vm.stopBroadcast();

    }
}