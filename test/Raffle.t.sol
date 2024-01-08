// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract RaffleUnitTest is Test, TestSetup {
    using Strings for uint256;

    event RaffleDrawn(uint256 tokenThreshold, uint256 requestId);
    event RafflePrizeAmountReceived(uint256 tokenThreshold, uint256 prizeAmount);
    event WinningsClaimed(address winner, uint256 amount);

    function setUp() public {
        _setUp();
        uint256 tokensToMint = 1999 - nft.getCurrentTokenId();
        util_mint_tokens(tokensToMint);
    }

    function test_deployment_Raffle() public {
        assertEq(address(raffle.VRF_COORDINATOR()), address(vrf));
        assertEq(address(raffle.ORC_NATION()), address(nft));
        assertEq(address(raffle.PAYMENT_SPLITTER()), address(paymentSplitter));
    }

    function test_util_functions_automate_raffle() public {
        util_mint_tokens(1);
        assertEq(nft.getCurrentTokenId(), 2000);
        assertTrue(raffle.raffleDrawn(2000));
        assertFalse(raffle.requestIds(2000) == 0);
    }

    ////////////////////////////
    ///   RAFFLE FUNCTIONS   ///
    ////////////////////////////

    function test_drawRaffle() public {
        uint threshold = 2000;
        assertEq(raffle.raffleDrawn(threshold), false);
        assertEq(raffle.requestIds(threshold), 0);
        vm.expectEmit(false, false, false, false);
        emit RaffleDrawn(threshold, 42);
        util_mint_tokens(1);
        // raffle is drawn when token threshold is reached 
        assertEq(raffle.raffleDrawn(threshold), true);
        // request ID is generated and stored
        assertFalse(raffle.requestIds(threshold) == 0);
        emit log_uint(raffle.requestIds(threshold));
        
        uint new_threshold = 4000;
        assertEq(raffle.raffleDrawn(new_threshold), false);
        assertEq(raffle.requestIds(new_threshold), 0);
        util_mint_tokens(new_threshold - threshold);
        // raffle is drawn when token new_threshold is reached 
        assertEq(raffle.raffleDrawn(new_threshold), true);
        // request ID is generated and stored
        assertFalse(raffle.requestIds(new_threshold) == 0);
        emit log_uint(raffle.requestIds(new_threshold));
    }

    // function test_drawRaffle_revert() public {}

    function test_selectRaffleWinners() public {
        uint threshold = 2000;
        address[] memory winners = raffle.getRaffleWinners(threshold);
        assertEq(raffle.raffleComplete(threshold), false);
        assertEq(winners.length, 0);
        util_mint_tokens_no_raffle_fulfill(1);
            // mock VRF 
        uint requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
        // initiated by fulfillRandomWords
        assertEq(raffle.raffleComplete(threshold), true);
        winners = raffle.getRaffleWinners(threshold);
        assertEq(winners.length, 5);
        // selects & stores valid winners 
        for(uint i; i < winners.length; ++i) {
            // no duplicates, no team members
            assertEq(paymentSplitter.isPayee(winners[i]), false);
            for(uint j; j < winners.length; ++j) {
                if(i != j) {
                    assertFalse(winners[i] == winners[j]);
                }
            }
        }
        // marks raffle complete
        assertEq(raffle.raffleComplete(threshold), true);
        // works across different raffles - fulfillRandomWords selects correct function
            // 4000
        uint256 oldThreshold = threshold;
        threshold = 4000;
        util_mint_tokens_no_raffle_fulfill(threshold - oldThreshold);
        requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
        assertEq(raffle.raffleComplete(threshold), true);
        winners = raffle.getRaffleWinners(threshold);
        assertEq(winners.length, 3);
        for(uint i; i < winners.length; ++i) {
            // no duplicates, no team members
            assertEq(paymentSplitter.isPayee(winners[i]), false);
            for(uint j; j < winners.length; ++j) {
                if(i != j) {
                    assertFalse(winners[i] == winners[j]);
                }
            }
        }

            // 6000
        oldThreshold = threshold;
        threshold = 6000;
        util_mint_tokens_no_raffle_fulfill(threshold - oldThreshold);
        requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
        assertEq(raffle.raffleComplete(threshold), true);
        winners = raffle.getRaffleWinners(threshold);
        assertEq(winners.length, 1);
        for(uint i; i < winners.length; ++i) {
            // no duplicates, no team members
            assertEq(paymentSplitter.isPayee(winners[i]), false);
            for(uint j; j < winners.length; ++j) {
                if(i != j) {
                    assertFalse(winners[i] == winners[j]);
                }
            }
        }

            // 10000
        oldThreshold = threshold;
        threshold = 10000;
        util_mint_tokens_no_raffle_fulfill(threshold - oldThreshold);
        requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
        assertEq(raffle.raffleComplete(threshold), true);
        winners = raffle.getRaffleWinners(threshold);
        assertEq(winners.length, 1);
        for(uint i; i < winners.length; ++i) {
            // no duplicates, no team members
            assertEq(paymentSplitter.isPayee(winners[i]), false);
            for(uint j; j < winners.length; ++j) {
                if(i != j) {
                    assertFalse(winners[i] == winners[j]);
                }
            }
        }

    }

    // function test_selectRaffleWinners_revert() public {}

    function test_raffle2000_winners_added_to_Orc_Nation() public {
        uint threshold = 2000;
        vm.prank(alice);
        nft.mint{value: priceOneToken}(alice, 1);
        uint requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
        address[] memory winners = raffle.getRaffleWinners(threshold);
        // winners have been added to Orc Nation and can mint a comp
        for(uint i; i < winners.length; ++i) {
            assertEq(nft.isCompMintRecipient(winners[i]), true);
            vm.prank(winners[i]);
            nft.mintComp();
        }

    }

    function test_receiveRaffleWinnings() public {
        vm.pauseGasMetering();
            // 2000
        uint threshold = 2000;
        util_mint_tokens_no_raffle_fulfill(1);
        uint requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
            // 4000
        uint256 oldThreshold = threshold;
        threshold = 4000;
        util_mint_tokens_no_raffle_fulfill(threshold - oldThreshold);
        requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
        vm.resumeGasMetering();
            // transfer from Payment splitter
        uint256 raffleContractBalBefore = address(raffle).balance;
        uint256 paymentSplitterContractaBalBefore = address(paymentSplitter).balance;
        (uint256[] memory prizes, uint256 prizeAmount) = paymentSplitter.getRafflePrizeAmount(threshold);
        bytes memory data = abi.encodeWithSignature("transferRaffleWinnings(uint256)", 4000);
        vm.prank(adminA);
        uint256 txIndex = governor.proposeTransaction(address(paymentSplitter), 0, data); 
        vm.expectEmit(false, false, false, true);
        emit RafflePrizeAmountReceived(threshold, prizeAmount);
        vm.prank(adminB);
        governor.signTransaction(txIndex);

        // value has been transferred
        assertEq(address(raffle).balance, raffleContractBalBefore + prizeAmount);
        assertEq(address(paymentSplitter).balance, paymentSplitterContractaBalBefore - prizeAmount);
        // winner amounts recorded
        address[] memory winners = raffle.getRaffleWinners(threshold);
        for(uint i; i < winners.length; ++i) {
            assertEq(raffle.getRaffleWinnings(winners[i]), prizes[i]);
        }

            // 6000
        oldThreshold = threshold;
        threshold = 6000;
        util_mint_tokens_no_raffle_fulfill(threshold - oldThreshold);
        requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
        vm.resumeGasMetering();
            // transfer from Payment splitter
        raffleContractBalBefore = address(raffle).balance;
        paymentSplitterContractaBalBefore = address(paymentSplitter).balance;
        (prizes, prizeAmount) = paymentSplitter.getRafflePrizeAmount(threshold);
        data = abi.encodeWithSignature("transferRaffleWinnings(uint256)", 6000);
        vm.prank(adminA);
        txIndex = governor.proposeTransaction(address(paymentSplitter), 0, data); 
        vm.expectEmit(false, false, false, true);
        emit RafflePrizeAmountReceived(threshold, prizeAmount);
        vm.prank(adminB);
        governor.signTransaction(txIndex);

        // value has been transferred
        assertEq(address(raffle).balance, raffleContractBalBefore + prizeAmount);
        assertEq(address(paymentSplitter).balance, paymentSplitterContractaBalBefore - prizeAmount);
        // winner amounts recorded
        winners = raffle.getRaffleWinners(threshold);
        for(uint i; i < winners.length; ++i) {
            assertEq(raffle.getRaffleWinnings(winners[i]), prizes[i]);
        }

            // 10000
        oldThreshold = threshold;
        threshold = 10000;
        util_mint_tokens_no_raffle_fulfill(threshold - oldThreshold);
        requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
        vm.resumeGasMetering();
            // transfer from Payment splitter
        raffleContractBalBefore = address(raffle).balance;
        paymentSplitterContractaBalBefore = address(paymentSplitter).balance;
        (prizes, prizeAmount) = paymentSplitter.getRafflePrizeAmount(threshold);
        data = abi.encodeWithSignature("transferRaffleWinnings(uint256)", 10000);
        vm.prank(adminA);
        txIndex = governor.proposeTransaction(address(paymentSplitter), 0, data); 
        vm.expectEmit(false, false, false, true);
        emit RafflePrizeAmountReceived(threshold, prizeAmount);
        vm.prank(adminB);
        governor.signTransaction(txIndex);

        // value has been transferred
        assertEq(address(raffle).balance, raffleContractBalBefore + prizeAmount);
        assertEq(address(paymentSplitter).balance, paymentSplitterContractaBalBefore - prizeAmount);
        // winner amounts recorded
        winners = raffle.getRaffleWinners(threshold);
        for(uint i; i < winners.length; ++i) {
            assertEq(raffle.getRaffleWinnings(winners[i]), prizes[i]);
        }
    }

    function test_claimRaffleWinnings() public {
        vm.pauseGasMetering();
            // 2000
        uint threshold = 2000;
        util_mint_tokens_no_raffle_fulfill(1);
        uint requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
            // 4000
        uint256 oldThreshold = threshold;
        threshold = 4000;
        util_mint_tokens_no_raffle_fulfill(threshold - oldThreshold);
        requestId = raffle.requestIds(threshold);
        vrf.fulfillRandomWords(requestId, address(raffle));
        (uint256[] memory prizes, uint256 prizeAmount) = paymentSplitter.getRafflePrizeAmount(threshold);
        bytes memory data = abi.encodeWithSignature("transferRaffleWinnings(uint256)", 4000);
        vm.prank(adminA);
        uint256 txIndex = governor.proposeTransaction(address(paymentSplitter), 0, data); 
        vm.expectEmit(false, false, false, true);
        emit RafflePrizeAmountReceived(threshold, prizeAmount);
        vm.prank(adminB);
        governor.signTransaction(txIndex);
        vm.resumeGasMetering();

        uint256 contractBalBefore = address(raffle).balance;
        uint256 amountClaimed;
        address[] memory winners = raffle.getRaffleWinners(4000);
        // winners can claim
        for(uint i; i < winners.length; ++i) {
            assertEq(raffle.hasClaimedWinnings(winners[i]), false);
            uint256 balBefore = winners[i].balance;
            uint256 raffleWinnings = raffle.getRaffleWinnings(winners[i]);
            vm.expectEmit(false, false, false, true);
            emit WinningsClaimed(winners[i], raffleWinnings);
            vm.prank(winners[i]);
            raffle.claimRaffleWinnings();
            amountClaimed += raffleWinnings;
            assertEq(winners[i].balance, balBefore + raffleWinnings);
            assertEq(raffle.hasClaimedWinnings(winners[i]), true);
        }
        assertEq(address(raffle).balance, contractBalBefore - amountClaimed);
    }

    // function test_claimRaffleWinnings_revert() public {}

    
}
