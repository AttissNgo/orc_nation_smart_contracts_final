// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Governor.sol";
import "../src/OrcNation.sol";
import "../src/PaymentSplitter.sol";
import "../src/Raffle.sol";
import "./PriceFeedMock.sol";
import "chainlink/VRFCoordinatorV2Mock.sol";
// import "solmate/src/utils/LibString.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract TestSetup is Test {

    Governor public governor;
    OrcNation public nft;
    PaymentSplitter public paymentSplitter;
    Raffle public raffle;
    PriceFeedMock public pricefeed;
    VRFCoordinatorV2Mock public vrf;

    // named addresses
    address public alice = vm.addr(1); 
    address public bob = vm.addr(2); 
    address public carlos = vm.addr(3);
    address public david = vm.addr(4);

    // 'owner' received initial 500 tokens
    // 'company' is the deployer and royalty receiver
    address public owner = vm.addr(5);
    address public company = vm.addr(13);
    address public adminA = vm.addr(6);
    address public adminB = vm.addr(7);
    address public teamMember1 = vm.addr(8);
    address public teamMember2 = vm.addr(9);
    address public teamMember3 = vm.addr(10);
    address public teamMember4 = vm.addr(11);
    address public teamMember5 = vm.addr(12);

    address public governorAddress;

    // bulk addresses
    address[] public buyers;
    address[] public users = [alice, bob, carlos, david];

    // governor
    address[] public admins = [owner, adminA, adminB];
    uint256 public signaturesNeeded = 2;

    // TODO - update for decimals
    // payment splitter
    address[] public payees = [
        governorAddress, 
        adminA, 
        adminB, 
        teamMember1,
        teamMember2, 
        teamMember3, 
        teamMember4, 
        teamMember5
    ];
    uint256[] public shares = [
        30, 
        15,
        15,
        10,
        5,
        5,
        5,
        5
    ];
    mapping(address => uint256) public payeeToSharesInternal;

    // variables
    uint64 public subscriptionId;
    string public uri = "ipfs://someuri/";
    uint256 public priceOneToken;
    uint256 public priceTwoTokens;
    uint256 public priceThreeTokens;
    uint256 public priceFourTokens;
    uint256 public priceFiveTokens;

    function _setUp() public {
        // deploy mocks
        pricefeed = new PriceFeedMock();
        vrf = new VRFCoordinatorV2Mock(1, 1);
        // fund VRF
        vm.startPrank(company);
        subscriptionId = vrf.createSubscription();
        vrf.fundSubscription(subscriptionId, 1 ether);
        // deploy governor 
        governor = new Governor(admins, signaturesNeeded);
        // add governor address to payee array
        payees[0] = address(governor);
        // deploy payment splitter// compute future raffle address
        uint64 nonce = vm.getNonce(company);
        // address computedRaffleAddr = computeCreateAddress(company, nonce + 2);
        address computedRaffleAddr = vm.computeCreateAddress(company, nonce + 2);
        paymentSplitter = new PaymentSplitter(
            payees, 
            shares, 
            address(pricefeed), 
            address(governor),
            computedRaffleAddr
        );
        // deploy Orc Nation 
        nft = new OrcNation(
            address(vrf),
            address(pricefeed),
            address(governor),
            address(paymentSplitter),
            computedRaffleAddr,
            owner,
            block.timestamp + 100,
            block.timestamp + 200,
            subscriptionId,
            uri
        );
        // deploy raffle
        raffle = new Raffle(
            address(vrf), 
            subscriptionId, 
            address(nft),
            address(paymentSplitter),
            address(governor)
        );
        vm.stopPrank();

        // record payee -> share internally for testing splitter
        for(uint i = 0; i < payees.length; ++i) {
            payeeToSharesInternal[payees[i]] = shares[i];
        }

        // intialize variables
        priceOneToken = nft.calculatePrice(1);
        priceTwoTokens = nft.calculatePrice(2);
        priceThreeTokens = nft.calculatePrice(3);
        priceFourTokens = nft.calculatePrice(4);
        priceFiveTokens = nft.calculatePrice(5);
        for(uint i = 1000; i < 2000; ++i) {
            address user = vm.addr(i);
            buyers.push(user);
        }

        // deal ether 
        for(uint i; i < buyers.length; ++i) {
            vm.deal(buyers[i], 1000 ether);
        }
        for(uint i; i < users.length; ++i) {
            vm.deal(users[i], 1000 ether);
        }

        //label
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carlos, "Carlos");
        vm.label(david, "David");
        vm.label(owner, "Owner");
        vm.label(adminA, "Admin A");
        vm.label(adminB, "Admin B");
        vm.label(company, "Company");
        vm.label(address(vrf), "VRF");
        vm.label(address(paymentSplitter), "Payment Splitter");
        vm.label(address(raffle), "Raffle Contract");
        vm.label(address(nft), "Orc Nation");

    }

    function util_executeGovernorTx(uint256 _txIndex) internal {
        for(uint i; i < admins.length; ++i) {
            Governor.Transaction memory transaction = governor.getTransaction(_txIndex);
            if(!governor.adminHasSigned(_txIndex, admins[i]) && transaction.numSignatures < governor.signaturesRequired()) {
                vm.prank(admins[i]);
                governor.signTransaction(_txIndex);
            }
        } 
    }

    //////////////////////////
    ///   TIME UTILITIES   ///
    //////////////////////////

    function warp_to_presale() public {
        vm.warp(nft.PRESALE());
    }

    function warp_to_sale_open() public {
        vm.warp(nft.SALE_OPEN());
    }

    /////////////////////////
    ///   MINTING CHEAT   ///
    /////////////////////////

    function util_mint_tokens(uint256 _numTokens) public {
        if(block.timestamp < nft.SALE_OPEN()) warp_to_sale_open();
        vm.pauseGasMetering();
        uint256 tokensMinted = 0;
        while(tokensMinted < _numTokens) {
            for(uint i; i < buyers.length; ++i) {
                if(tokensMinted >= _numTokens) break;
                uint256 numMints = 5;
                if(numMints + tokensMinted > _numTokens) {
                    numMints = _numTokens - tokensMinted;
                }
                if(numMints == 0) break;
                uint256 value = nft.calculatePrice(numMints);
                if(buyers[i].balance < value) {
                    vm.deal(buyers[i], value);
                }
                vm.prank(buyers[i]);
                uint256 requestId = nft.mint{value: value}(buyers[i], numMints);
                vrf.fulfillRandomWords(requestId, address(nft));
                tokensMinted += numMints;
            }
        }
        util_handle_raffle_fulfillment();
        vm.resumeGasMetering();
    }

    uint256[] public raffleThresholds = [2000, 4000, 6000, 10000];

    function util_handle_raffle_fulfillment() public {
        for(uint i; i < raffleThresholds.length; ++i) {
            if(nft.getCurrentTokenId() < raffleThresholds[0]) return;
            if(!raffle.raffleDrawn(raffleThresholds[i])) break;
            if(!raffle.raffleComplete(raffleThresholds[i])) {
                console.log("Fullfilling: %s", raffleThresholds[i]);
                uint256 requestId = raffle.requestIds(raffleThresholds[i]);
                vrf.fulfillRandomWords(requestId, address(raffle));
            }
        }
    }

    function util_mint_tokens_no_raffle_fulfill(uint256 _numTokens) public {
        if(block.timestamp < nft.SALE_OPEN()) warp_to_sale_open();
        vm.pauseGasMetering();
        uint256 tokensMinted = 0;
        while(tokensMinted < _numTokens) {
            for(uint i; i < buyers.length; ++i) {
                if(tokensMinted >= _numTokens) break;
                uint256 numMints = 5;
                while(numMints + tokensMinted > _numTokens) {
                    numMints = _numTokens - tokensMinted;
                }
                if(numMints == 0) break;
                uint256 value = nft.calculatePrice(numMints);
                if(buyers[i].balance < value) {
                    vm.deal(buyers[i], value);
                }
                vm.prank(buyers[i]);
                uint256 requestId = nft.mint{value: value}(buyers[i], numMints);
                vrf.fulfillRandomWords(requestId, address(nft));
                tokensMinted += numMints;
            }
        }
        vm.resumeGasMetering();
    }

}