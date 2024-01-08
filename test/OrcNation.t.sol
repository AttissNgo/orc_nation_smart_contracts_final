// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/OrcNation.sol";
import "../src/PaymentSplitter.sol";
import "../src/Raffle.sol";
import "./PriceFeedMock.sol";
import "chainlink/VRFCoordinatorV2Mock.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./TestSetup.sol";
import "forge-std/console.sol";

contract OrcNationTest is Test, TestSetup {
    using Strings for uint256;

    address dummyAddr = vm.addr(999);

    event VRFRequestCreated(uint256 requestId);

    function setUp() public {
        _setUp();
    }

    //////////////////////
    ///   DEPLOYMENT   ///
    //////////////////////

    function test_deployment_OrcNation() public {
        assertEq(address(nft.VRF_COORDINATOR()), address(vrf));
        assertEq(address(nft.PRICEFEED()), address(pricefeed));
        assertEq(address(nft.PAYMENT_SPLITTER()), address(paymentSplitter));
        assertEq(address(nft.RAFFLE()), address(raffle));
        assertEq(address(nft.GOVERNOR()), address(governor));
        assertEq(nft.getRoyaltyReceiver(), company);
        assertEq(nft.getBaseUri(), uri);
        assertEq(nft.PRESALE(), block.timestamp + 100);
        assertEq(nft.SALE_OPEN(), block.timestamp + 200);
        assertEq(nft.subscriptionId(), subscriptionId);
    }

    function test_initialMint_success() public {
        assertEq(nft.getCurrentTokenId(), 500);
        // owner account has 500 tokens
        assertEq(nft.balanceOf(owner), 500);
        // tokens have URIs
        for(uint i = 1; i <= 500; ++i) {
            assertFalse(nft.tokenIdToUriExtension(i) == 0);
            // console.log(nft.tokenIdToUriExtension(i));
        }
        assertTrue(nft.initialMintClaimed());
    }

    function test_initialMint_gas() public {
        vm.pauseGasMetering();
        nft = new OrcNation(
            address(vrf),
            address(pricefeed),
            address(governor),
            address(paymentSplitter),
            address(raffle),
            owner,
            block.timestamp + 100,
            block.timestamp + 200,
            subscriptionId,
            uri
        );
        vm.resumeGasMetering();
        vm.prank(owner);
        nft.initialMint();
    }

    function test_initialMint_revert() public {
        // deploy new instance
        vm.pauseGasMetering();
        nft = new OrcNation(
            address(vrf),
            address(pricefeed),
            address(governor),
            address(paymentSplitter),
            address(raffle),
            owner,
            block.timestamp + 100,
            block.timestamp + 200,
            subscriptionId,
            uri
        );
        vm.resumeGasMetering();

        // not inital mint recipient
        vm.expectRevert(OrcNation.OrcNation__OnlyInitialMintRecipient.selector);
        vm.prank(alice);
        nft.initialMint();

        // already claimed
        vm.prank(owner);
        nft.initialMint();
        vm.expectRevert(OrcNation.OrcNation__InitialMintAlreadyClaimed.selector);
        vm.prank(owner);
        nft.initialMint();

        // reverts if claimed late - not enough tokens
        // vm.pauseGasMetering();
        // nft = new OrcNation(
        //     address(vrf),
        //     address(pricefeed),
        //     address(governor),
        //     address(paymentSplitter),
        //     address(raffle),
        //     owner,
        //     block.timestamp + 100,
        //     block.timestamp + 200,
        //     subscriptionId,
        //     uri
        // );
        // vm.resumeGasMetering();

    }

    function test_constructor_errors() public {
        vm.expectRevert(OrcNation.OrcNation__InvalidSaleTime.selector);
        new OrcNation(
            address(vrf),
            address(pricefeed),
            address(governor),
            address(paymentSplitter),
            dummyAddr,
            owner,
            block.timestamp + 300, // presale > sale
            block.timestamp + 200,
            subscriptionId,
            uri
        );
        vm.expectRevert(OrcNation.OrcNation__InvalidSaleTime.selector);
        new OrcNation(
            address(vrf),
            address(pricefeed),
            address(governor),
            address(paymentSplitter),
            dummyAddr,
            owner,
            block.timestamp - 1, // presale < now
            block.timestamp + 200,
            subscriptionId,
            uri
        );
    }

    /////////////////////
    ///   MODIFIERS   ///
    /////////////////////
    
    function test_onlyGovernor_modifier() public {
        vm.expectRevert(OrcNation.OrcNation__OnlyGovernor.selector);
        vm.prank(owner);
        nft.reducePrice(64);
    }

    function test_onlyAdmin_modifier() public {
        vm.expectRevert(OrcNation.OrcNation__OnlyAdmin.selector);
        vm.prank(alice);
        nft.assignCompMint(alice);
    }
 
    ///////////////////
    ///   ROYALTY   ///
    ///////////////////

    function test_setRoyaltyReceiver() public {
        assertEq(nft.getRoyaltyReceiver(), company);
        bytes memory data = abi.encodeWithSignature("setRoyaltyReceiver(address)", alice);
        vm.prank(owner);
        uint256 txIndex = governor.proposeTransaction(address(nft), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(nft.getRoyaltyReceiver(), alice);
    }

    function test_setRoyaltyReceiver_revert_zero_address() public {
        vm.expectRevert();
        vm.prank(owner);
        nft.setRoyaltyReceiver(address(0));
    }

    function test_royaltyInfo() public {
        uint256 salePrice = 100 ether;
        (address receiver, uint256 royalty) = nft.royaltyInfo(1, salePrice);
        assertEq(receiver, company);
        assertEq(royalty, (salePrice * nft.ROYALTY_BASIS_POINTS())/10000);
    }

    function test_royaltyInfo_revert_nonexistant_token() public {
        vm.expectRevert();
        nft.royaltyInfo(10001, 0);
        vm.expectRevert();
        nft.royaltyInfo(0, 0);
    }

    /////////////////////
    ///   WHITELIST   ///
    /////////////////////

    function test_addToWhitelist() public {
        assertEq(nft.getWhitelistCount(), 0);
        vm.prank(owner);
        nft.addToWhitelist(users);
        assertEq(nft.getWhitelistCount(), users.length);
        for(uint i = 0; i < users.length; ++i) {
            assertEq(nft.isWhitelisted(users[i]), true);
        }
        assertEq(nft.getWhitelistCount(), users.length);
    }

    function test_whitelist_discount() public {
        vm.prank(owner);
        nft.addToWhitelist(users);
        warp_to_presale();
        uint256 whitelistPrice = nft.calculatePrice(1);
        vm.prank(alice);
        nft.mint{value: whitelistPrice}(alice, 1);
        warp_to_sale_open();
        uint256 fullPrice = nft.calculatePrice(1);
        assertEq((fullPrice * 85)/100, whitelistPrice);
    }

    function test_whitelist_mint_revert() public {
        vm.prank(owner);
        nft.addToWhitelist(users);
        warp_to_presale();
        uint256 whitelistPrice = nft.calculatePrice(3);
        // exceed max whitelist mints
        vm.prank(alice);
        nft.mint{value: whitelistPrice}(alice, 3);
        whitelistPrice = nft.calculatePrice(1);
        vm.expectRevert(OrcNation.OrcNation__MaxThreePresaleMintsPerWhitelistedAddress.selector);
        vm.prank(alice);
        nft.mint{value: whitelistPrice}(alice, 1);
    }

    function test_addToWhitelist_revert_max_whitelistees() public {
        uint256 tooManyAddresses = nft.MAX_WHITELISTEES() + 1;
        address[] memory whitelistees = new address[](tooManyAddresses);
        for(uint i = 0; i < whitelistees.length; ++i) {
            whitelistees[i] = buyers[i];
        }
        vm.expectRevert(OrcNation.OrcNation__WillExceedMaxWhitelistees.selector);
        vm.prank(owner);
        nft.addToWhitelist(whitelistees);
    }

    ///////////////////
    ///   MINTING   ///
    ///////////////////

    function test_mint() public {
        uint256 numTokensBefore = nft.getCurrentTokenId();
        uint256 paymentSplitterBalBefore = address(paymentSplitter).balance;
        uint256 remainingUrisBefore = nft.remainingUris();
        assertEq(nft.getBuyers().length, 0);
        assertFalse(nft.isBuyer(alice));

        warp_to_sale_open();

        uint256 numMints = 5;
        uint256 value = nft.calculatePrice(numMints);
        uint256 expectedVRFRequestId = 1;
        vm.expectEmit(false, false, false, true);
        emit VRFRequestCreated(expectedVRFRequestId);
        vm.prank(alice);
        uint256 requestId = nft.mint{value: value}(alice, numMints);
        uint256[] memory batchTokens = nft.getBatchTokens(requestId);
        assertEq(batchTokens.length, numMints);
        assertEq(nft.getCurrentTokenId(), numTokensBefore + numMints);
        assertEq(address(paymentSplitter).balance, paymentSplitterBalBefore + value);
        assertEq(nft.getBuyers().length, 1);
        assertTrue(nft.isBuyer(alice));
        
        // fulfill VRF request
        vrf.fulfillRandomWords(requestId, address(nft));
        // uris assigned
        assertEq(nft.remainingUris(), remainingUrisBefore - numMints);
        for(uint i; i < batchTokens.length; ++i) {
            assertTrue(nft.tokenIdToUriExtension(batchTokens[i]) != 0);
        }
    }

    function test_mint_revert() public {
        uint256 value = nft.calculatePrice(1);
        // minting not open
        vm.expectRevert(OrcNation.OrcNation__MintingNotOpen.selector);
        vm.prank(alice);
        nft.mint{value: value}(alice, 1);

        warp_to_presale();

        // presale - not whitelisted
        assertFalse(nft.isWhitelisted(alice));
        vm.expectRevert(OrcNation.OrcNation__NotWhitelisted.selector);
        vm.prank(alice);
        nft.mint{value: value}(alice, 1);

        // presale - max presale exceeded
        vm.prank(adminA);
        nft.addToWhitelist(users);
        assertTrue(nft.isWhitelisted(alice));
        value = nft.calculatePrice(3);
        vm.prank(alice);
        nft.mint{value: value}(alice, 3);
        vm.expectRevert(OrcNation.OrcNation__MaxThreePresaleMintsPerWhitelistedAddress.selector);
        vm.prank(alice);
        nft.mint{value: value}(alice, 3);

        warp_to_sale_open();

        // zero mints
        vm.expectRevert(OrcNation.OrcNation__MustMintAtLeastOneToken.selector);
        vm.prank(alice);
        nft.mint(alice, 0);

        // max mints per tx exceeded
        value = nft.calculatePrice(11);
        vm.expectRevert(OrcNation.OrcNation__MaxMintsPerTransactionExceeded.selector);
        vm.prank(alice);
        nft.mint{value: value}(alice, 11);

        // insufficient payment
        value = nft.calculatePrice(1);
        bytes4 selector = bytes4(keccak256("OrcNation__InsufficientPayment(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, value));
        vm.prank(alice);
        nft.mint{value: value - 1}(alice, 1);

        // total supply exceeded
        vm.pauseGasMetering();
        while(nft.getCurrentTokenId() < nft.MAX_SUPPLY()) {
            for(uint i; i < buyers.length; ++i) {
                if(nft.getCurrentTokenId() == nft.MAX_SUPPLY()) break;
                vm.prank(buyers[i]);
                nft.mint{value: value}(buyers[i], 1);
            }
        }
        vm.resumeGasMetering();
        assertEq(nft.getCurrentTokenId(), nft.MAX_SUPPLY());
        vm.expectRevert(OrcNation.OrcNation__WillExceedMaxSupply.selector);
        vm.prank(alice);
        nft.mint{value: value}(alice, 1);
    }

    function test_assignCompMint() public {
        assertEq(nft.getCompMintCount(), 0);
        assertFalse(nft.isCompMintRecipient(alice));
        vm.prank(owner);
        nft.assignCompMint(alice);
        assertEq(nft.getCompMintCount(), 1);
        assertTrue(nft.isCompMintRecipient(alice));
    }

    function test_assignCompMint_revert() public {

        warp_to_sale_open();

        // duplicate address
        vm.prank(owner);
        nft.assignCompMint(alice);
        vm.expectRevert(OrcNation.OrcNation__CompMintAlreadyAssignedToAddress.selector);
        vm.prank(owner);
        nft.assignCompMint(alice);
        
        // already claimed comp
        vm.prank(owner);
        nft.assignCompMint(bob);
        vm.prank(bob);
        nft.mintComp();
        vm.expectRevert(OrcNation.OrcNation__CompMintAlreadyClaimed.selector);
        vm.prank(owner);
        nft.assignCompMint(bob);

        // max comps exceeded
        uint256 i = 0;
        while(nft.getCompMintCount() < nft.MAX_COMP_MINTS()) {
            vm.prank(owner);
            nft.assignCompMint(buyers[i]);
            ++i;
        }
        assertEq(nft.getCompMintCount(), nft.MAX_COMP_MINTS());
        vm.expectRevert(OrcNation.OrcNation__MaxCompMintsExceeded.selector);
        vm.prank(owner);
        nft.assignCompMint(carlos);
    }

    function test_mintComp() public {
        vm.prank(owner);
        nft.assignCompMint(alice);
        warp_to_presale();
        vm.prank(alice);
        uint256 requestId = nft.mintComp();
        assertEq(nft.ownerOf(nft.getBatchTokens(requestId)[0]), alice);
        assertEq(nft.hasClaimedCompMint(alice), true);
    }

    function test_mintComp_revert() public {
        // already claimed
        vm.prank(owner);
        nft.assignCompMint(alice);
        warp_to_presale();
        vm.prank(alice);
        nft.mintComp();
        assertTrue(nft.hasClaimedCompMint(alice));
        vm.expectRevert(OrcNation.OrcNation__CompMintAlreadyClaimed.selector);
        vm.prank(alice);
        nft.mintComp();

        // not comp recipient
        assertFalse(nft.isCompMintRecipient(bob));
        vm.expectRevert(OrcNation.OrcNation__NotEligibleForCompMint.selector);
        vm.prank(bob);
        nft.mintComp();
    } 

    /////////////////////
    ///   TOKEN URI   ///
    /////////////////////

    mapping(uint256 => bool) urisUsed;

    function test_all_uris_unique() public {
        vm.pauseGasMetering();

        warp_to_sale_open();

        // console.log(nft.getCurrentTokenId());
        // console.log(nft.remainingUris());

        // mint all tokens & assign URIs
        uint256 value = nft.calculatePrice(1);
        while(nft.getCurrentTokenId() < nft.MAX_SUPPLY()) {
            for(uint i; i < buyers.length; ++i) {
                if(nft.getCurrentTokenId() == nft.MAX_SUPPLY()) break;
                vm.prank(buyers[i]);
                uint256 requestId = nft.mint{value: value}(buyers[i], 1);
                vrf.fulfillRandomWords(requestId, address(nft));
            }
        }
        assertEq(nft.getCurrentTokenId(), nft.MAX_SUPPLY());

        // populate mapping with uri extensions - check for duplicates
        for(uint i = 1; i <= 10000; ++i) {
            // if(nft.tokenIdToUriExtension(i) == 0) console.log(i);
            assertFalse(urisUsed[nft.tokenIdToUriExtension(i)]);
            urisUsed[nft.tokenIdToUriExtension(i)] = true;
        }
        vm.resumeGasMetering();
    }

    function test_tokenURI() public {
        for(uint i = 1; i <= 500; ++i) {
            uint256 uriExt = nft.tokenIdToUriExtension(i);
            string memory expectedUri = string.concat(nft.getBaseUri(), uriExt.toString(), ".json");
            assertEq(expectedUri, nft.tokenURI(i));
        }
    }


}