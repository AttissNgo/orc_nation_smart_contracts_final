// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Governor.sol";
import "../src/OrcNation.sol";
import "../src/PaymentSplitter.sol";
import "../test/PriceFeedMock.sol";
import "chainlink/VRFCoordinatorV2Mock.sol";

contract DeploymentLib is Script {

    // contracts
    PriceFeedMock public pricefeedMock;
    VRFCoordinatorV2Mock public vrfMock;
    Governor public governor;
    PaymentSplitter public paymentSplitter;
    OrcNation public nft;
    address[] public contractAddresses;

    // sale
    uint256 presaleTime;
    uint256 publicSaleTime;

    // EOAs
    address public royaltyReceiver;
    address[] public admins;
    address[] public payees;
    uint256[] public shares;

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

    function _deployMocks() internal {
        pricefeedMock = new PriceFeedMock();

        vrfMock = new VRFCoordinatorV2Mock(1, 1);
        subscriptionId = vrfMock.createSubscription();
        vrfMock.fundSubscription(subscriptionId, 10 ether);

        pricefeedAddress = address(pricefeedMock);
        vrfAddress = address(vrfMock);
        
    }

    function _deployContracts() internal {
        governor = new Governor(admins, sigsRequired);
        payees[0] = address(governor);

        paymentSplitter = new PaymentSplitter(
            payees, 
            shares, 
            address(governor)
        );

        nft = new OrcNation(
            vrfAddress,
            pricefeedAddress,
            address(governor),
            address(paymentSplitter),
            royaltyReceiver,
            presaleTime, 
            publicSaleTime, 
            subscriptionId,
            baseUri
        );
    }

    function _setContractNames(
        address _pricefeed,
        address _vrf,
        address _governor,
        address _paymentSplitter,
        address _orcNation
    ) 
        internal 
    {
        contractNames[_pricefeed] = "Pricefeed";
        contractAddresses.push(_pricefeed);
        contractNames[_vrf] = "VRF";
        contractAddresses.push(_vrf);
        contractNames[_governor] = "Governor";
        contractAddresses.push(_governor);
        contractNames[_paymentSplitter] = "PaymentSplitter";
        contractAddresses.push(address(paymentSplitter));
        contractNames[_orcNation] = "OrcNation";
        contractAddresses.push(_orcNation);
    }

    function _serializeAddr(
        string memory _object, 
        string memory _keyName, 
        address _addr
    ) 
        internal
        returns (string memory)
    {
        string memory serializedAddress = vm.serializeAddress(_object, _keyName, _addr);
        return serializedAddress;
    }

    function _writeToJsonOut(string memory _serializedValue, string memory _filePath, string memory _valueKey) internal {
        vm.writeJson(_serializedValue, _filePath, _valueKey);
    }

    function _copyAbisFromOut() internal {
        string memory orcNationAbi = vm.readFile("./out/OrcNation.sol/OrcNation.json");
        string memory path = "./json_out/OrcNationAbi.json";
        vm.writeFile(path, orcNationAbi);
        
        string memory governorAbi = vm.readFile("./out/Governor.sol/Governor.json");
        path = "./json_out/GovernorAbi.json";
        vm.writeFile(path, governorAbi);

        string memory paymentSplitterAbi = vm.readFile("./out/PaymentSplitter.sol/PaymentSplitter.json");
        path = "./json_out/PaymentSplitterAbi.json";
        vm.writeFile(path, paymentSplitterAbi);
    }

}

contract DeploymentLocal is DeploymentLib {

    address[] public anvilAdmins = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // anvil 0
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // anvil 1
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC // anvil 2
    ];
    address[] public anvilPayees = [
        address(0), // this gets changed to Governor address in run()
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
        0x90F79bf6EB2c4f870365E785982E1f101E93b906
    ];

    uint256[] public anvilShares = [
        5000, 2000, 2000, 1000
    ];

    function setUp() public {
        // set EOAs
        royaltyReceiver = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // anvil 0
        for(uint i; i < anvilAdmins.length; ++i) {
            admins.push(anvilAdmins[i]);
        }
        for(uint i; i < anvilPayees.length; ++i) {
            payees.push(anvilPayees[i]);
            shares.push(anvilShares[i]);
        }
        // pricefeed & vrf config set in run()
        // sale times
        presaleTime = block.timestamp + 100;
        publicSaleTime = block.timestamp + 200;
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

        _deployMocks();

        _deployContracts();
        
        vm.stopBroadcast();
        
        // set names
        _setContractNames(
            address(pricefeedMock),
            address(vrfMock),
            address(governor),
            address(paymentSplitter),
            address(nft)
        );

        // write addresses to json
        for(uint i; i < contractAddresses.length; ++i) {
            _writeToJsonOut(
                _serializeAddr(obj1, contractNames[contractAddresses[i]], contractAddresses[i]),
                "./json_out/deployedAddresses.json", 
                addressValueKey
            );
        }

        _copyAbisFromOut();

    }  
}


contract DeploymentMumbai is DeploymentLib {

    address[] public mumbaiAdmins = [
        0x98779c48C6f426c0eF632EefA8981e05ecB1910C, // johan (personal)
        0x537Df8463a09D0370DeE4dE077178300340b0030, // attiss dev0
        0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // attiss dev1
        0xDE12A4d649A27e1280ce1a8ceFc0483d38276968 // femi
    ];

    address[] public mumbaiPayees = [
        address(0), // this gets changed to Governor address in run()
        0xA1Fa78C32C15a316436c243Bc3DABf9529c303a6, // radniel
        0xA4f65508C82130622Bda6a507d5606BC4A420bFa, // jenelle
        0xf0ce0cc50d7fdF9145b606Fa6B9b1880192E77d6, // prachi
        0xB4BF6C646ceD30964Ab33F5C1dc61828167debd7, // ernsesto
        0x52e34Eb7568F794797525f65De29f6FA569d8D34, // martin
        0x741395400a3C09776C7208e4407ADA95344ef158, // rodger
        0x322f441eD1d1dA7a26fd888128143A097C17c167, // head marketing
        0x4E43501dA8d45736d4e48D058cAad66CcC0b05B4, // johan
        0x537Df8463a09D0370DeE4dE077178300340b0030, // attiss dev0
        0x0aeE152ceF9fC90C975fdFD186e649fbbcE259e4, // shree
        0x48f25eF02FF0daC0666cCA23fFBb7759c146f8d9, // trevor
        0xDE12A4d649A27e1280ce1a8ceFc0483d38276968, // femi
        0x44a6bf09A58faA2033a26A0bD5A91F982F21Cd3B, // discord 4 / set 1
        0x9b660b7106FBd0d7F334Bb3F7b5F08a8602535fe // discord 4 / set 2
    ];

    uint256[] public mumbaiShares = [
        2954, // company -- added %0.02 to make it all add up to 100%
        345, //radniel
        345, // jenelle
        345, // prachi
        353, // ernesto
        353, // martin
        531, // rodger
        690, // head marketing
        1698, // johan
        424, // attiss
        424, // shree
        424, // trevor
        424, // femi
        345, // discord 4 / set 1
        345 // discord 4 / set 2
    ];

    function setUp() public {
        // splitter checks
        uint256 sharesSum;
        // set EOAs
        royaltyReceiver = 0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa; // attiss dev1 -
        for(uint i; i < mumbaiAdmins.length; ++i) {
            admins.push(mumbaiAdmins[i]);
        }
        for(uint i; i < mumbaiPayees.length; ++i) {
            payees.push(mumbaiPayees[i]);
            shares.push(mumbaiShares[i]);
            sharesSum += mumbaiShares[i];
        }
        require(sharesSum == 10000, "shares don't total 100%");
        require(payees.length == shares.length, "mismatched addresses -> shares");
        // pricefeed & vrf config 
        subscriptionId = 2867; // make sure consumers are set!
        pricefeedAddress = 0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada; // mumbai testnet
        vrfAddress = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed; // mumbai testnet
        // sale times
        presaleTime = block.timestamp + 60;
        publicSaleTime = block.timestamp + 2 days;
        // uri & governance
        baseUri = "ipfs://bafybeibrqntuuyzaz4sh7hs244rxlvksvcqrgzm6a5z3hedphdcsfse3gm/"; 
        sigsRequired = 2;
        // set json variables
        obj1 = "mumbai";
        addressValueKey = ".mumbai";
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("MUMBAI_PK_0"); // attiss dev0 account
        vm.startBroadcast(deployerPrivateKey);
        
        _deployContracts();

        vm.stopBroadcast();

        // set names
        _setContractNames(
            pricefeedAddress,
            vrfAddress,
            address(governor),
            address(paymentSplitter),
            address(nft)
        );

        // write addresses to json
        for(uint i; i < contractAddresses.length; ++i) {
            _writeToJsonOut(
                _serializeAddr(obj1, contractNames[contractAddresses[i]], contractAddresses[i]),
                "./json_out/deployedAddresses.json", 
                addressValueKey
            );
        }

        _copyAbisFromOut();

    }
}

contract DeploymentPolygon is DeploymentLib {

    address[] public polygonAdmins = [
        0x4E43501dA8d45736d4e48D058cAad66CcC0b05B4, // johan (personal)
        0xd5C53b14D0F213Fe8E4EdbDB5Aca5b61D63b3D5f, // attiss (trust)
        0x4A3F12706E154ed0A73D13dE18704f4e88231fb3 // femi
    ];

    address[] public polygonPayees = [
        address(0), // company --- this gets changed to Governor address in run()
        0xA1Fa78C32C15a316436c243Bc3DABf9529c303a6, // radniel
        0xA4f65508C82130622Bda6a507d5606BC4A420bFa, // jenelle
        0xf0ce0cc50d7fdF9145b606Fa6B9b1880192E77d6, // prachi
        0xB4BF6C646ceD30964Ab33F5C1dc61828167debd7, // ernesto
        0x52e34Eb7568F794797525f65De29f6FA569d8D34, // martin
        0x741395400a3C09776C7208e4407ADA95344ef158, // rodger
        0x322f441eD1d1dA7a26fd888128143A097C17c167, // 'revenue share'
        0x4E43501dA8d45736d4e48D058cAad66CcC0b05B4, // johan
        0xd5C53b14D0F213Fe8E4EdbDB5Aca5b61D63b3D5f, // attiss (trust)
        0x0aeE152ceF9fC90C975fdFD186e649fbbcE259e4, // shree
        0x48f25eF02FF0daC0666cCA23fFBb7759c146f8d9, // trevor
        0x512139DFaBb2848694dfD9B48e9a1Aa9264A0fA8, // femi
        0x44a6bf09A58faA2033a26A0bD5A91F982F21Cd3B, // discord 4 / set 1
        0x9b660b7106FBd0d7F334Bb3F7b5F08a8602535fe // discord 4 / set 2
    ];

    uint256[] public polygonShares = [
        3316, // company
        280, //radniel
        375, // jenelle
        275, // prachi
        375, // ernesto
        220, // martin
        540, // rodger
        675, // revenue share
        1675, // johan
        475, // attiss
        424, // shree
        180, // trevor
        500, // femi
        345, // discord 4 / set 1
        345 // discord 4 / set 2
    ];

    function setUp() public {
        // splitter checks
        uint256 sharesSum;
        // set EOAs
        royaltyReceiver = 0x4E43501dA8d45736d4e48D058cAad66CcC0b05B4; // johan royaltyReceiver address
        for(uint i; i < polygonAdmins.length; ++i) {
            admins.push(polygonAdmins[i]);
        }
        for(uint i; i < polygonPayees.length; ++i) {
            payees.push(polygonPayees[i]);
            shares.push(polygonShares[i]);
            sharesSum += polygonShares[i];
        }
        require(sharesSum == 10000, "shares don't total 100%");
        require(payees.length == shares.length, "mismatched addresses -> shares");
        // pricefeed & vrf config 
        subscriptionId = 1119; 
        pricefeedAddress = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0; // polygon mainnet
        vrfAddress = 0xAE975071Be8F8eE67addBC1A82488F1C24858067; // polygon mainnet
        // sale times
        presaleTime = 1710529200; // 15 March 2024 12:00pm PST
        publicSaleTime = 1711134000; // 22 March 2024 12:00pm PST
        // uri & governance
        baseUri = "bafybeigxu4n6gnjt6ka4ugfgckyqwzff4oxc27jj5y7ifcomvp7pdtcuoe/"; 
        sigsRequired = 2;
        // set json variables
        obj1 = "polygon";
        addressValueKey = ".polygon";
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("POLYGON_PK_0"); 
        vm.startBroadcast(deployerPrivateKey);
        
        _deployContracts();

        vm.stopBroadcast();

        // set names
        _setContractNames(
            pricefeedAddress,
            vrfAddress,
            address(governor),
            address(paymentSplitter),
            address(nft)
        );

        // write addresses to json
        for(uint i; i < contractAddresses.length; ++i) {
            _writeToJsonOut(
                _serializeAddr(obj1, contractNames[contractAddresses[i]], contractAddresses[i]),
                "./json_out/deployedAddresses.json", 
                addressValueKey
            );
        }

        _copyAbisFromOut();

    }
}