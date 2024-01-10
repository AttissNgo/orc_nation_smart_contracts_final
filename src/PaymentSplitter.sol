// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Interfaces/IRaffle.sol";
import "./Interfaces/IPricefeed.sol";

contract PaymentSplitter {

    IPricefeed public immutable PRICEFEED;
    address public immutable GOVERNOR;
    IRaffle public immutable RAFFLE;
    
    uint256 private totalReleased;
    uint256 private totalShares;
    mapping(address => uint256) private share; 
    mapping(address => uint256) private amountReleased; 
    address[] private payees;
    mapping(address => bool) public isPayee;

    // raffle
    uint256 public constant RAFFLE_4000_FIRST_PRIZE_USD = 2500;
    uint256 public constant RAFFLE_4000_SECOND_PRIZE_USD = 500;
    uint256 public constant RAFFLE_4000_THIRD_PRIZE_USD = 100;
    uint256 public constant RAFFLE_6000_PRIZE_USD = 5000;
    uint256 public constant RAFFLE_FINAL_GRAND_PRIZE_USD = 10000;

    event FundsReceived(address from, uint256 amount);
    event PayeeAdded(address payee, uint256 share);
    event PaymentTransferred(address payee, address recipient, uint256 amount);
    event RaffleWinningsTransferred(uint256 tokenThreshold, uint256 amount);

    error PaymentSplitter__NoPayees();
    error PaymentSplitter__PayeesAndSharesMismatched();
    error PaymentSplitter__SharesMustTotalOneHundredPercent();
    error PaymentSplitter__PayeeIsZeroAddress();
    error PaymentSplitter__ShareIsZero();
    error PaymentSplitter__DuplicatePayeeAddress();
    error PaymentSplitter__OnlyGovernor();
    error PaymentSplitter__NoPaymentDue();
    error PaymentSplitter__InsufficientContractBalance();
    error PaymentSplitter__PaymentTransferFailed();
    error PaymentSplitter__GovernorMustBeFirstPayeeAccount();
    error PaymentSplitter__PriceFeedAnswerNegative();
    error PaymentSplitter__RaffleNotComplete();
    error PaymentSplitter__InvalidRaffle();
    error PaymentSplitter__RaffleTransferFailed();
    error PaymentSplitter__CompanyMustUseClaimCompanyShare();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert PaymentSplitter__OnlyGovernor();
        _;
    }

    constructor(
        address[] memory _payees, 
        uint256[] memory _shares,
        address _pricefeed,
        address _governor,
        address _raffle
    ) 
        payable 
    {
        if(_payees.length == 0) revert PaymentSplitter__NoPayees();
        if(_payees.length != _shares.length) revert PaymentSplitter__PayeesAndSharesMismatched();
        if(_governor != _payees[0]) revert PaymentSplitter__GovernorMustBeFirstPayeeAccount();
        uint256 shareSum = 0;
        for(uint i; i < _shares.length; ) {
            shareSum += _shares[i];
            unchecked {++i;}
        }
        // shares must total exactly 10000 ... 10000/100 = 100%
        if(shareSum != 10000) revert PaymentSplitter__SharesMustTotalOneHundredPercent();
        GOVERNOR = _governor;
        PRICEFEED = IPricefeed(_pricefeed);
        RAFFLE = IRaffle(_raffle);
        for(uint i = 0; i < _payees.length; ++i) {
            _addPayee(_payees[i], _shares[i]);
        }
    }

    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    function claimShare() external {
        if(msg.sender == GOVERNOR) revert PaymentSplitter__CompanyMustUseClaimCompanyShare();
        uint256 payment = _transferShare(msg.sender, msg.sender);
        emit PaymentTransferred(msg.sender, msg.sender, payment);
    }

    function claimCompanyShare(address _recipient) external onlyGovernor {
        uint256 payment = _transferShare(msg.sender, _recipient);
        emit PaymentTransferred(msg.sender, _recipient, payment);
    }

    function _transferShare(address _claimant, address _recipient) private returns (uint256){
        if(share[_claimant] == 0) revert PaymentSplitter__ShareIsZero();
        uint256 payment = paymentDue(_claimant);
        if(payment == 0) revert PaymentSplitter__NoPaymentDue();
        if(address(this).balance < payment) revert PaymentSplitter__InsufficientContractBalance();
        totalReleased += payment;
        unchecked{ amountReleased[_claimant] += payment; } // cannot overflow if totalReleased didn't overflow
        (bool success, ) = payable(_recipient).call{value: payment}("");
        if(!success) revert PaymentSplitter__PaymentTransferFailed();
        return payment;
    }

    // transfer RAFFLE PRIZES
    function convertToMATIC(uint256 _amountInUSD) public view returns (uint256) {
        (,int price,,,) = PRICEFEED.latestRoundData();
        if(price < 0) revert PaymentSplitter__PriceFeedAnswerNegative();
        int256 decimals = int256(10 ** PRICEFEED.decimals());
        int256 usdPriceDecimals = int256(_amountInUSD * 1e18);
        return uint256(usdPriceDecimals / price * decimals);
    }

    function transferRaffleWinnings(uint256 _tokenThreshold) external onlyGovernor {
        if(!RAFFLE.raffleComplete(_tokenThreshold)) revert PaymentSplitter__RaffleNotComplete();
        (uint[] memory prizes, uint256 totalPrizeAmount) = getRafflePrizeAmount(_tokenThreshold);
        if(totalPrizeAmount == 0) revert PaymentSplitter__InvalidRaffle();
        if(address(this).balance < totalPrizeAmount) revert PaymentSplitter__InsufficientContractBalance();
        // subtract from company shares
        totalReleased += totalPrizeAmount;
        amountReleased[GOVERNOR] += totalPrizeAmount; 
        RAFFLE.receiveRafflePrize{value: totalPrizeAmount}(_tokenThreshold, prizes);
        emit RaffleWinningsTransferred(_tokenThreshold, totalPrizeAmount);
    }

    function getRafflePrizeAmount(uint256 _tokenThreshold) public view returns (uint256[] memory, uint256) {
        if(_tokenThreshold != 4000 && _tokenThreshold != 6000 && _tokenThreshold != 10000) {
            revert PaymentSplitter__InvalidRaffle();
        }
        if(_tokenThreshold == 4000) {
            // uint256 firstPrize = convertToMATIC(RAFFLE_4000_FIRST_PRIZE_USD);
            // uint256 secondPrize = convertToMATIC(RAFFLE_4000_SECOND_PRIZE_USD);
            // uint256 thirdPrize = convertToMATIC(RAFFLE_4000_THIRD_PRIZE_USD);

            // MUMBAI test prize amounts:
            uint256 firstPrize = convertToMATIC(RAFFLE_4000_FIRST_PRIZE_USD) / 100000;
            uint256 secondPrize = convertToMATIC(RAFFLE_4000_SECOND_PRIZE_USD) / 100000;
            uint256 thirdPrize = convertToMATIC(RAFFLE_4000_THIRD_PRIZE_USD) / 100000;

            uint256[] memory prizes = new uint256[](3);
            prizes[0] = firstPrize;
            prizes[1] = secondPrize;
            prizes[2] = thirdPrize;
            return(prizes, firstPrize + secondPrize + thirdPrize);
        } else if (_tokenThreshold == 6000) {
            // uint256 prizeAmount = convertToMATIC(RAFFLE_6000_PRIZE_USD);

            // MUMBAI test prize amount:
            uint256 prizeAmount = convertToMATIC(RAFFLE_6000_PRIZE_USD) / 100000;

            uint256[] memory prizes = new uint256[](1);
            prizes[0] = prizeAmount;
            return(prizes, prizeAmount);
        } else {
            // uint256 prizeAmount = convertToMATIC(RAFFLE_FINAL_GRAND_PRIZE_USD);

            // MUMBAI test prize amount
            uint256 prizeAmount = convertToMATIC(RAFFLE_FINAL_GRAND_PRIZE_USD) / 100000;
            
            uint256[] memory prizes = new uint256[](1);
            prizes[0] = prizeAmount;
            return(prizes, prizeAmount);
        }
    }

    function _addPayee(address _payee, uint256 _share) private {
        if(_payee == address(0)) revert PaymentSplitter__PayeeIsZeroAddress();
        if(_share == 0) revert PaymentSplitter__ShareIsZero();
        if(share[_payee] != 0) revert PaymentSplitter__DuplicatePayeeAddress();
        payees.push(_payee);
        isPayee[_payee] = true;
        share[_payee] = _share;
        totalShares += _share;
        emit PayeeAdded(_payee, _share);
    }

    function paymentDue(address payee) public view returns (uint256) {
        uint256 totalReceived = getTotalReceived();
        uint256 payment = _percentage((totalReceived * share[payee]) / totalShares) - amountReleased[payee];
        return payment;
    }

    function _percentage(uint256 _amount) private pure returns (uint256) {
        return _amount/100;
    } 

    // getters 
    function getTotalReceived() public view returns (uint256) {
        return address(this).balance + totalReleased;
    }

    function getTotalReleased() public view returns (uint256) {
        return totalReleased;
    }

    function getTotalShares() public view returns (uint256) {
        return totalShares;
    }

    function getShare(address payee) public view returns (uint256) {
        return share[payee];
    }

    function getAmountReleased(address payee) public view returns (uint256) {
        return amountReleased[payee];
    }

    function getPayees() public view returns (address[] memory) {
        return payees;
    }
    
}
