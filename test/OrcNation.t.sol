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

    function test_initialMint() public {
        assertEq(nft.getCurrentTokenId(), 500);
        // owner account has 500 tokens
        assertEq(nft.balanceOf(owner), 500);
        // tokens have URIs
        for(uint i = 1; i <= 500; ++i) {
            assertFalse(nft.tokenIdToUriExtension(i) == 0);
            // console.log(nft.tokenIdToUriExtension(i));
        }
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
        // address[] memory whitelistees = new address[](3);
        // whitelistees[0] = alice;
        // whitelistees[1] = bob;
        // whitelistees[2] = carlos;
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

}