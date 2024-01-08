// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Governor.sol";
import "../src/OrcNation.sol";
import "../src/PaymentSplitter.sol";
import "../src/Raffle.sol";
import "../test/PriceFeedMock.sol";
import "chainlink/VRFCoordinatorV2Mock.sol";

contract DeploymentLib is Script {

    // contracts
    PriceFeedMock public pricefeedMock;
    VRFCoordinatorV2Mock public vrfMock;
    Governor public governor;
    PaymentSplitter public paymentSplitter;
    OrcNation public nft;
    Raffle public raffle;
    address[] public contractAddresses;

    // Chainlink
    address public pricefeedAddress;
    address public vrfAddress;
    uint64 public subscriptionId;

    // uri & governance
    string public baseUri;
    uint256 public sigsRequired;

    // JSON variables
    mapping(address => string) public contractNames;
    string public obj1;
    string public addressValueKey;


    function serializeABI() public {}

    function serializeAddr(
        string memory _object, 
        string memory _keyName, 
        address _addr
    ) 
        public 
        returns (string memory)
    {
        string memory serializedAddress = vm.serializeAddress(_object, _keyName, _addr);
        return serializedAddress;
    }

    function writeToJsonOut(
        string memory _serializedValue,
        string memory _filePath,
        string memory _valueKey
    )
        public
    {
        vm.writeJson(_serializedValue, _filePath, _valueKey);
    }

}

contract DeploymentLocal is DeploymentLib {

    

    address public initialMintRecipient = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address[] public admins = [
        initialMintRecipient,
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
    ];
    address[] public payees = [
        address(0), // this gets changed to Governor address in run()
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
        0x90F79bf6EB2c4f870365E785982E1f101E93b906
    ];

    uint256[] public shares = [
        5000, 2000, 2000, 1000
    ];

    function setUp() public {

        // uri & governance
        baseUri = "ipfs://bafybeihtjotnsuu5zgv2miitn6garjwfavprkivrjswixcm73sbyrpusxy/"; //dummy image - production rarity
        sigsRequired = 2;
        // set json variables
        obj1 = "local";
        addressValueKey = ".anvil";
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PK_0");
        vm.startBroadcast(deployerPrivateKey);

        pricefeedMock = new PriceFeedMock();
        pricefeedAddress = address(pricefeedMock);
        contractNames[pricefeedAddress] = "Pricefeed";
        contractAddresses.push(pricefeedAddress);

        vrfMock = new VRFCoordinatorV2Mock(1, 1);
        subscriptionId = vrfMock.createSubscription();
        vrfMock.fundSubscription(subscriptionId, 10 ether);
        vrfAddress = address(vrfMock);
        contractNames[vrfAddress] = "VRF";
        contractAddresses.push(vrfAddress);

        governor = new Governor(admins, sigsRequired);
        payees[0] = address(governor);
        contractNames[address(governor)] = "Governor";
        contractAddresses.push(address(governor));

        uint64 nonce = vm.getNonce(vm.addr(deployerPrivateKey));
        console.log("nonce: ", nonce);
        address computedRaffleAddr = vm.computeCreateAddress(vm.addr(deployerPrivateKey), nonce + 2);
        paymentSplitter = new PaymentSplitter(
            payees, 
            shares, 
            pricefeedAddress, 
            address(governor),
            computedRaffleAddr
        );
        contractNames[address(paymentSplitter)] = "PaymentSplitter";
        contractAddresses.push(address(paymentSplitter));

        nft = new OrcNation(
            vrfAddress,
            pricefeedAddress,
            address(governor),
            address(paymentSplitter),
            computedRaffleAddr,
            initialMintRecipient,
            block.timestamp + 100, 
            block.timestamp + 200, 
            subscriptionId,
            baseUri
        );
        contractNames[address(nft)] = "OrcNation";
        contractAddresses.push(address(nft));

        raffle = new Raffle(
            vrfAddress, 
            subscriptionId, 
            address(nft),
            address(paymentSplitter),
            address(governor)
        );
        contractNames[address(raffle)] = "Raffle";
        contractAddresses.push(address(raffle));

        vm.stopBroadcast();
        
        // write addresses to json
        for(uint i; i < contractAddresses.length; ++i) {
            string memory serializedAddress = serializeAddr(obj1, contractNames[contractAddresses[i]], contractAddresses[i]);
            writeToJsonOut(serializedAddress, "./json_out/deployedAddresses.json", addressValueKey);
        }

        // string memory obj1 = "local";
        // string memory valueKey = ".anvil";
        // string memory pricefeedAddr = serializeAddr(obj1, "PricefeedAddress", pricefeedAddress);
        // writeToJsonOut(pricefeedAddr, "./json_out/deployedAddresses.json", addressValueKey);


        // string memory vrfAddr = serializeAddr(obj1, "VRFAddress", vrfAddress);
        // vm.writeJson(vrfAddr, "./deploymentInfo.json", valueKey);
        // string memory govAddr = vm.serializeAddress(obj1, "GovernorAddress", address(governor));
        // vm.writeJson(govAddr, "./deploymentInfo.json", valueKey);
        // string memory paymentsAddr = vm.serializeAddress(obj1, "PaymentSplitterAddress", address(paymentSplitter));
        // vm.writeJson(paymentsAddr, "./deploymentInfo.json", valueKey);
        // string memory nftAddr = vm.serializeAddress(obj1, "OrcNationAddress", address(nft));
        // vm.writeJson(nftAddr, "./deploymentInfo.json", valueKey);
        // string memory raffleAddr = vm.serializeAddress(obj1, "RaffleAddress", address(raffle));
        // vm.writeJson(raffleAddr, "./deploymentInfo.json", valueKey);
    }  
}


// TODO: Inherit from base lib contract
// TODO: Change all addresses 
// TODO: Change all shares


contract DeploymentMumbai is Script {

    Governor public governor;
    PaymentSplitter public paymentSplitter;
    OrcNation public nft;
    Raffle public raffle;

    uint64 subscriptionId = 2867; // make sure consumers are set!
    address pricefeedAddress = 0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada; 
    address vrfAddress = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed; 
    string public baseUri = "ipfs://bafybeihtjotnsuu5zgv2miitn6garjwfavprkivrjswixcm73sbyrpusxy/"; //dummy image - production rarity
    uint256 public sigsRequired = 2;

    address public initialMintRecipient = 0x537Df8463a09D0370DeE4dE077178300340b0030; // attiss 
    address[] public admins = [
        0x537Df8463a09D0370DeE4dE077178300340b0030, // attiss 
        0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // attiss
        0x3ED5730ede564191166d9EA4E8C36B9fda4f3AeD, // femi
        0xa7135743f8D68eF9e9ba15BC8B572ff88f2226B6, // johan
        0x48f25eF02FF0daC0666cCA23fFBb7759c146f8d9, // trevor
        0xc8385892266137043F1302Bf800BADe1f93A1A49, // trevor
        0x0aeE152ceF9fC90C975fdFD186e649fbbcE259e4, // shree
        0xc222bEE93e7CcD814611a8d3401C8Dbb1A4aA237 // shree
    ];

    address[] public payees = [
        address(0), // this gets changed to Governor address in run()
        0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // attiss
        0xDE12A4d649A27e1280ce1a8ceFc0483d38276968, // femi
        0x4E43501dA8d45736d4e48D058cAad66CcC0b05B4, // johan
        0x48f25eF02FF0daC0666cCA23fFBb7759c146f8d9, // trevor
        0x0aeE152ceF9fC90C975fdFD186e649fbbcE259e4 //shree
    ];

    uint256[] public shares = [50, 10, 10, 10, 10, 10];

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("MUMBAI_PK_0");
        vm.startBroadcast(deployerPrivateKey);
        governor = new Governor(admins, sigsRequired);
        payees[0] = address(governor);
        uint64 nonce = vm.getNonce(vm.addr(deployerPrivateKey));
        address computedRaffleAddr = vm.computeCreateAddress(vm.addr(deployerPrivateKey), nonce + 2);
        paymentSplitter = new PaymentSplitter(
            payees, 
            shares, 
            pricefeedAddress, 
            address(governor),
            computedRaffleAddr
        );
        nft = new OrcNation(
            vrfAddress,
            pricefeedAddress,
            address(governor),
            address(paymentSplitter),
            computedRaffleAddr,
            initialMintRecipient,
            block.timestamp + 100, 
            block.timestamp + 200, 
            subscriptionId,
            baseUri
        );
        raffle = new Raffle(
            vrfAddress, 
            subscriptionId, 
            address(nft),
            address(paymentSplitter),
            address(governor)
        );

        vm.stopBroadcast();

        // write addresses to json
        string memory obj1 = "some key";
        string memory valueKey = ".mumbai";
        string memory pricefeedAddr = vm.serializeAddress(obj1, "PricefeedAddress", pricefeedAddress);
        vm.writeJson(pricefeedAddr, "./deploymentInfo.json", valueKey);
        string memory vrfAddr = vm.serializeAddress(obj1, "VRFAddress", vrfAddress);
        vm.writeJson(vrfAddr, "./deploymentInfo.json", valueKey);
        string memory govAddr = vm.serializeAddress(obj1, "GovernorAddress", address(governor));
        vm.writeJson(govAddr, "./deploymentInfo.json", valueKey);
        string memory paymentsAddr = vm.serializeAddress(obj1, "PaymentSplitterAddress", address(paymentSplitter));
        vm.writeJson(paymentsAddr, "./deploymentInfo.json", valueKey);
        string memory nftAddr = vm.serializeAddress(obj1, "OrcNationAddress", address(nft));
        vm.writeJson(nftAddr, "./deploymentInfo.json", valueKey);
        string memory raffleAddr = vm.serializeAddress(obj1, "RaffleAddress", address(raffle));
        vm.writeJson(raffleAddr, "./deploymentInfo.json", valueKey);
    }
}