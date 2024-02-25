// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.sol";

contract PaymentSplitterUnitTest is Test, TestSetup {

    uint256 receiveAmount = 100 ether;

    event FundsReceived(address from, uint256 amount);
    event PayeeAdded(address payee, uint256 share);
    event PaymentTransferred(address payee, address recipient, uint256 amount);

    function setUp() public {
        _setUp();
        // governorNotFirst[1] = address(governor);
        // payeesWithZeroAddress[0] = address(governor);
        vm.deal(address(paymentSplitter), receiveAmount);
    }

    //////////////////////
    ///   DEPLOYMENT   ///
    //////////////////////

    function test_deployement() public {
        assertEq(paymentSplitter.getPayees(), payees);
        for(uint i = 0; i < payees.length; ++i) {
            assertEq(paymentSplitter.getShare(payees[i]), shares[i]);
        }
        assertEq(address(paymentSplitter.GOVERNOR()), address(governor));
    }

    function test_constructor_revert() public {
        // no payees
        address[] memory noPayees = new address[](0);
        uint256[] memory noShares = new uint256[](0);
        vm.expectRevert(PaymentSplitter.PaymentSplitter__NoPayees.selector);
        paymentSplitter = new PaymentSplitter(
            noPayees, 
            noShares, 
            address(governor)
        );
        // company (governor) not first payee
        address[] memory governorNotFirst = payees;
        governorNotFirst[0] = governorNotFirst[1];
        governorNotFirst[1] = address(governor);
        vm.expectRevert(PaymentSplitter.PaymentSplitter__GovernorMustBeFirstPayeeAccount.selector);
        paymentSplitter = new PaymentSplitter(
            governorNotFirst, 
            shares, 
            address(governor)
        );
        // shares do not total to 100%
        uint256[] memory sharesNot100Percent = shares;
        sharesNot100Percent[0] += 1; // add 1 point to first share
        vm.expectRevert(PaymentSplitter.PaymentSplitter__SharesMustTotalOneHundredPercent.selector);
        paymentSplitter = new PaymentSplitter(
            payees, 
            sharesNot100Percent, 
            address(governor)
        );
        // payees & shares mismatched
        shares.push(42); // add another share
        vm.expectRevert(PaymentSplitter.PaymentSplitter__PayeesAndSharesMismatched.selector);
        paymentSplitter = new PaymentSplitter(
            payees, 
            // mismatchedShares, 
            shares,
            address(governor)
        );
    }

    function test_addPayee_revert() public {
        // zero address
        address[] memory payeesWithZeroAddress = payees;
        payeesWithZeroAddress[1] = address(0);
        vm.expectRevert(PaymentSplitter.PaymentSplitter__PayeeIsZeroAddress.selector);
        paymentSplitter = new PaymentSplitter(
            payeesWithZeroAddress, 
            shares, 
            address(governor)
        );
        // share is 0
        uint256[] memory sharesWithZeroAmount = shares;
        sharesWithZeroAmount[1] += sharesWithZeroAmount[0]; // add [0] share to [1] so total is still 100%
        sharesWithZeroAmount[0] = 0;
        vm.expectRevert(PaymentSplitter.PaymentSplitter__ShareIsZero.selector);
        paymentSplitter = new PaymentSplitter(
            payees,
            sharesWithZeroAmount,
            address(governor)
        );
        // duplicate payee address
        address[] memory payeesWithDuplicate = payees;
        payeesWithDuplicate[1] = payeesWithDuplicate[0];
        vm.expectRevert(PaymentSplitter.PaymentSplitter__DuplicatePayeeAddress.selector);
        paymentSplitter = new PaymentSplitter(
            payeesWithDuplicate,
            shares,
            address(governor)
        );
    }

    ///////////////////////////
    ///   CLAIMING SHARES   ///
    ///////////////////////////

    function test_receive() public {
        vm.deal(alice, receiveAmount);
        vm.expectEmit(true, true, false, false);
        emit FundsReceived(alice, receiveAmount);
        vm.prank(alice);
        (bool success,) = payable(address(paymentSplitter)).call{value: receiveAmount}("");
        require(success);
    }

    function test_paymentDue() public {
        uint256 totalReceived = paymentSplitter.getTotalReceived();
        assertEq(totalReceived, receiveAmount);
        assertEq(paymentSplitter.getTotalReleased(), 0); 
        // nothing has been released, so payment due should be: ((totalReceived * share)/totalShares)
        uint256 index = 1;
        assertEq(payees[index], owner);
        assertEq(
            paymentSplitter.paymentDue(owner), 
            ((totalReceived * paymentSplitter.getShare(owner))) / paymentSplitter.getTotalShares() 
        );
    }

    function test_claimShare() public {
        assertEq(address(paymentSplitter).balance, receiveAmount);
        uint256 contractBalBefore = address(paymentSplitter).balance;
        uint256 payees1BalBefore = payees[1].balance;
        uint256 payees1ClaimAmount_1 = paymentSplitter.paymentDue(payees[1]);
        vm.expectEmit(false, false, false, true);
        emit PaymentTransferred(payees[1], payees[1], payees1ClaimAmount_1);
        vm.prank(payees[1]);
        paymentSplitter.claimShare();
        assertEq(payees[1].balance, payees1BalBefore + payees1ClaimAmount_1);
        assertEq(address(paymentSplitter).balance, contractBalBefore - payees1ClaimAmount_1);

        contractBalBefore = address(paymentSplitter).balance;
        uint256 payees2BalBefore = payees[2].balance;
        uint256 payees2ClaimAmount_1 = paymentSplitter.paymentDue(payees[2]);
        vm.prank(payees[2]);
        paymentSplitter.claimShare();
        assertEq(payees[2].balance, payees2BalBefore + payees2ClaimAmount_1);
        assertEq(address(paymentSplitter).balance, contractBalBefore - payees2ClaimAmount_1);

        // more funds added
        vm.deal(alice, receiveAmount);
        vm.prank(alice);
        (bool success,) = payable(address(paymentSplitter)).call{value: receiveAmount}("");
        require(success);

        contractBalBefore = address(paymentSplitter).balance;
        payees1BalBefore = payees[1].balance;
        uint256 payees1ClaimAmount_2 = paymentSplitter.paymentDue(payees[1]);
        uint256 payees1ExpectedAmount = (((receiveAmount * 2) * shares[1]) / 10000) - payees1ClaimAmount_1;
        assertEq(payees1ClaimAmount_2, payees1ExpectedAmount);
        vm.prank(payees[1]);
        paymentSplitter.claimShare();
        assertEq(payees[1].balance, payees1BalBefore + payees1ClaimAmount_2);
        assertEq(address(paymentSplitter).balance, contractBalBefore - payees1ClaimAmount_2);
    }

    function test_claimShare_revert() public {
        // zero share
        assertFalse(paymentSplitter.isPayee(alice));
        vm.expectRevert(PaymentSplitter.PaymentSplitter__ShareIsZero.selector);
        vm.prank(alice);
        paymentSplitter.claimShare();
        // no payment due
        vm.prank(teamMember1);
        paymentSplitter.claimShare();
        vm.expectRevert(PaymentSplitter.PaymentSplitter__NoPaymentDue.selector);
        vm.prank(teamMember1);
        paymentSplitter.claimShare();
        // governor calls claimShare instead of claimCompanyShare
        bytes memory data = abi.encodeWithSignature("claimShare()");
        vm.prank(adminA);
        uint256 txIndex = governor.proposeTransaction(address(paymentSplitter), 0, data);
        vm.expectRevert();
        vm.prank(adminB);
        governor.signTransaction(txIndex);
    }
    
    function test_claimCompanyShare() public {
        assertEq(address(paymentSplitter).balance, receiveAmount);
        uint256 contractBalBefore = address(paymentSplitter).balance;
        uint256 recipientBalBefore = alice.balance;
        uint256 expectedAmount = paymentSplitter.paymentDue(address(governor));
        bytes memory data = abi.encodeWithSignature("claimCompanyShare(address)", alice);
        vm.prank(adminA);
        uint256 txIndex = governor.proposeTransaction(address(paymentSplitter), 0, data);
        vm.expectEmit(false, false, false, true);
        emit PaymentTransferred(address(governor), alice, expectedAmount);
        util_executeGovernorTx(txIndex);
        assertEq(alice.balance, recipientBalBefore + expectedAmount);
        assertEq(address(paymentSplitter).balance, contractBalBefore - expectedAmount);
    }

}