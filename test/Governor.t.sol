// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "../src/Governor.sol";

contract GovernorTest is Test {
    Governor public governor;

    address admin1 = vm.addr(1);
    address admin2 = vm.addr(2);
    address admin3 = vm.addr(3);
    address notAdmin = vm.addr(4);

    address[] admins = [admin1, admin2, admin3];
    uint256 numSignatures = 2;

    address[] duplicateAdmins = [admin1, admin1, admin2, admin3];

    uint256 testValue = 42 ether;

    event TransactionProposed(
        uint256 txIndex,
        address to,
        uint256 value,
        bytes data,
        address proposedBy
    );
    event TransactionSigned(uint256 txIndex, address admin, uint256 numSignatures);
    event TransactionExecuted(uint256 txIndex, address to, uint256 value, bytes data);
    event SignatureRevoked(uint256 txIndex, address admin, uint256 numSignatures);
    event TransactionCancelled(uint256 txIndex);
    event AdminAdded(address newAdmin);
    event AdminRemoved(address adminRemoved);
    event SignaturesRequiredChanged(uint256 signaturesRequired);

    /// @dev unit test only - does not set up whole contract ecosystem
    function setUp() public {
        governor = new Governor(admins, numSignatures);
    }

    //////////////////////
    ///   DEPLOYMENT   ///
    //////////////////////

    function test_deployment() public {
        // admins recorded
        for(uint i; i < admins.length; ++i) {
            assertTrue(governor.isAdmin(admins[i]));
        }
        // signatures recorded
        assertEq(governor.signaturesRequired(), numSignatures);
    }

    function test_constructor_revert() public {
        // duplicate admins
        vm.expectRevert(Governor.Governor__DuplicateAdminAddress.selector);
        governor = new Governor(duplicateAdmins, numSignatures);
        // too many sigs required
        vm.expectRevert(Governor.Governor__TooManySignaturesRequired.selector);
        governor = new Governor(admins, admins.length +1);
        // too few sigs required
        vm.expectRevert(Governor.Governor__TooFewSignaturesRequired.selector);
        governor = new Governor(admins, 1);
    }

    /////////////////////
    ///   MODIFIERS   ///
    /////////////////////

    function test_onlyAdmin_modifier() public {
        vm.expectRevert(Governor.Governor__OnlyAdmin.selector);
        vm.prank(notAdmin);
        governor.proposeTransaction(admin1, 0, "");
    }

    function test_onlyActive_modifier() public {
        // tx doesn't exist
        vm.expectRevert(); // should revert with array out-of-bounds panic
        vm.prank(admin1);
        governor.signTransaction(666);
        // tx already executed
        uint256 txIndex = _tx_with_value();
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        Governor.Transaction memory transaction = governor.getTransaction(txIndex);
        assertTrue(transaction.executed);
        vm.expectRevert(Governor.Governor__TransactionNotActive.selector);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
    }

    function test_onlyGovernor_modifier() public {
        vm.expectRevert(Governor.Governor__OnlyGovernor.selector);
        vm.prank(admin1);
        governor.addAdmin(notAdmin);
    }

    ///////////////////////
    ///   TRANSACTIONS  ///
    ///////////////////////

    function test_proposeTransaction() public {
        Governor.Transaction[] memory numTxs = governor.getAllTransactions();
        vm.expectEmit(false, false, false, true);
        emit TransactionProposed(numTxs.length, admin2, testValue, "", admin1);
        uint256 txIndex = _tx_with_value();
        
        assertEq(governor.getAllTransactions().length, numTxs.length + 1);
        Governor.Transaction memory transaction = governor.getTransaction(txIndex);
        assertEq(transaction.to, admin2);
        assertEq(transaction.value, testValue);
        assertEq(transaction.data, "");
        assertEq(transaction.proposedBy, admin1);
        assertEq(transaction.active, true);
        assertEq(transaction.executed, false);
        assertEq(transaction.numSignatures, 1);

        assertTrue(governor.adminHasSigned(txIndex, admin1));
    }

    function test_signTransaction() public {
        uint256 txIndex = _tx_with_value();
        Governor.Transaction memory transaction = governor.getTransaction(txIndex);
        assertFalse(governor.adminHasSigned(txIndex, admin2));
        uint256 initialSigs = transaction.numSignatures;

        vm.expectEmit(false, false, false, true);
        emit TransactionSigned(txIndex, admin2, initialSigs + 1);
        vm.prank(admin2);
        governor.signTransaction(txIndex);

        // signature recorded
        transaction = governor.getTransaction(txIndex);
        assertEq(transaction.numSignatures, initialSigs + 1);
        assertTrue(governor.adminHasSigned(txIndex, admin2));

        // if enough sigs, tx should be executed ... in this case it's true
        if(transaction.numSignatures >= governor.signaturesRequired()) {
            assertTrue(transaction.executed);
            assertFalse(transaction.active);
        }
    }

    function test_signTransaction_revert() public {
        // already signed
        uint256 txIndex = _tx_with_value();
        assertTrue(governor.adminHasSigned(txIndex, admin1));

        vm.expectRevert(Governor.Governor__DuplicateSignature.selector);
        vm.prank(admin1);
        governor.signTransaction(txIndex);
    }

    function test_executeTransaction() public {
        // increase then decrease sigs required!
        bytes memory data = abi.encodeWithSignature("changeSignaturesRequired(uint256)", 3);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);

        bytes memory dataToExecute = abi.encodeWithSignature("addAdmin(address)", notAdmin);
        vm.prank(admin1);
        uint256 txIndexToExecute = governor.proposeTransaction(address(governor), 0, dataToExecute);
        vm.prank(admin2);
        governor.signTransaction(txIndexToExecute);

        data = abi.encodeWithSignature("changeSignaturesRequired(uint256)", 2);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.prank(admin3);
        governor.signTransaction(txIndex);

        vm.expectEmit(false, false, false, true);
        emit TransactionExecuted(txIndexToExecute, address(governor), 0 , dataToExecute);
        vm.prank(admin2);
        governor.executeTransaction(txIndexToExecute);

        assertTrue(governor.isAdmin(notAdmin));
    }

    function test_revokeSignature() public {
        uint256 txIndex = _tx_with_value();
        Governor.Transaction memory transaction = governor.getTransaction(txIndex);
        uint256 initialSigs = transaction.numSignatures;
        assertTrue(governor.adminHasSigned(txIndex, admin1));
        vm.expectEmit(false, false, false, true);
        emit SignatureRevoked(txIndex, admin1, initialSigs - 1);
        vm.prank(admin1);
        governor.revokeSignature(txIndex);

        transaction = governor.getTransaction(txIndex);
        assertEq(transaction.numSignatures, initialSigs - 1);
        assertFalse(governor.adminHasSigned(txIndex, admin1));
    }

    function test_revokeSignature_revert() public {
        // has not signed
        uint256 txIndex = _tx_with_value();
        assertFalse(governor.adminHasSigned(txIndex, admin2));
        vm.expectRevert(Governor.Governor__UserHasNotSigned.selector);
        vm.prank(admin2);
        governor.revokeSignature(txIndex);
    }

    function test_cancelTransaction() public {
        uint256 txIndex = _tx_with_value();
        vm.expectEmit(false, false, false, true);
        emit TransactionCancelled(txIndex);
        vm.prank(admin1);
        governor.cancelTransaction(txIndex);

        Governor.Transaction memory transaction = governor.getTransaction(txIndex);
        assertFalse(transaction.active);
    }

    function test_cancelTransaction_revert() public {
        uint256 txIndex = _tx_with_value();
        Governor.Transaction memory transaction = governor.getTransaction(txIndex);
        assertFalse(transaction.proposedBy == admin2);
        vm.expectRevert(Governor.Governor__OnlyProposerCanCancel.selector);
        vm.prank(admin2);
        governor.cancelTransaction(txIndex);
    }

    /////////////////////////////////
    ///   ADMIN & SIG FUNCTIONS   ///
    /////////////////////////////////

    function test_addAdmin() public {
        assertFalse(governor.isAdmin(notAdmin));
        bytes memory data = abi.encodeWithSignature("addAdmin(address)", notAdmin);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.expectEmit(false, false, false, true);
        emit AdminAdded(notAdmin);
        vm.prank(admin2);
        governor.signTransaction(txIndex);

        assertTrue(governor.isAdmin(notAdmin));
        address[] memory newAdmins = governor.getAdmins();
        assertEq(newAdmins.length, admins.length + 1);
    }

    function test_addAdmin_revert() public {
        // duplicate address
        bytes memory data = abi.encodeWithSignature("addAdmin(address)", admin2);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);  
        vm.prank(admin2);
        governor.signTransaction(txIndex);

        // zero address
        data = abi.encodeWithSignature("addAdmin(address)", address(0));
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);  
        vm.prank(admin2);
        governor.signTransaction(txIndex);
    }

    function test_removeAdmin() public {
        bytes memory data = abi.encodeWithSignature("removeAdmin(address)", admin2);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.expectEmit(false, false, false, true);
        emit AdminRemoved(admin2);
        vm.prank(admin2);
        governor.signTransaction(txIndex);

        assertFalse(governor.isAdmin(admin2));
        assertEq(governor.getAdmins().length, admins.length - 1);
    }

    function test_removeAdmin_signature_update() public {
        // increase sigs, then remove admin
        bytes memory data = abi.encodeWithSignature("changeSignaturesRequired(uint256)", 3);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        assertEq(governor.signaturesRequired(), 3);

        data = abi.encodeWithSignature("removeAdmin(address)", admin2);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        
        assertEq(governor.getAdmins().length, 2);
        assertEq(governor.signaturesRequired(), 2);
    }

    function test_removeAdmin_revert() public {
        // not admin
        bytes memory data = abi.encodeWithSignature("removeAdmin(address)", notAdmin);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);
        vm.prank(admin2);
        governor.signTransaction(txIndex);

        // fewer than 2 admins
        data = abi.encodeWithSignature("removeAdmin(address)", admin3);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        data = abi.encodeWithSignature("removeAdmin(address)", admin2);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
    }

    function test_changeSignaturesRequired() public {
        uint256 initialSigsRequired = governor.signaturesRequired();
        bytes memory data = abi.encodeWithSignature("changeSignaturesRequired(uint256)", 3);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.expectEmit(false, false, false, true);
        emit SignaturesRequiredChanged(3);
        vm.prank(admin2);
        governor.signTransaction(txIndex);

        assertEq(governor.signaturesRequired(), initialSigsRequired + 1);
    }

    function test_changeSignaturesRequired_revert() public {
        bytes memory data = abi.encodeWithSignature("changeSignaturesRequired(uint256)", 5);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
    }

    /////////////////
    ///   UTILS   ///
    /////////////////

    function _tx_with_value() public returns (uint256) {
        vm.deal(address(governor), testValue);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(admin2, testValue, "");
        return txIndex;
    }

    function _execute_tx(uint256 _txIndex) public {
        for(uint256 i; i < admins.length; ++i) {
            Governor.Transaction memory transaction = governor.getTransaction(_txIndex);
            if(transaction.executed) break;
            else if(!governor.adminHasSigned(_txIndex, admins[i])) {
                vm.prank(admins[i]);
                governor.signTransaction(_txIndex);
            }
        }
    }

}
