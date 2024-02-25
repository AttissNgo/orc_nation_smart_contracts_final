// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract PaymentSplitter {

    address public immutable GOVERNOR;
    
    uint256 private totalReleased;
    uint256 private totalShares; 
    mapping(address => uint256) private share; // represented as basis points, i.e. 50% == 5000
    mapping(address => uint256) private amountReleased; 
    address[] private payees;
    mapping(address => bool) public isPayee;

    event FundsReceived(address from, uint256 amount);
    event PayeeAdded(address payee, uint256 share);
    event PaymentTransferred(address payee, address recipient, uint256 amount);

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
    error PaymentSplitter__CompanyMustUseClaimCompanyShare();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert PaymentSplitter__OnlyGovernor();
        _;
    }

    constructor(
        address[] memory _payees, 
        uint256[] memory _shares,
        address _governor
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
        // uint256 payment = _percentage((totalReceived * share[payee]) / totalShares) - amountReleased[payee];
        uint256 payment = ((totalReceived * share[payee]) / totalShares) - amountReleased[payee];

        return payment;
    }

    // function _percentage(uint256 _amount) private pure returns (uint256) {
    //     return _amount/100;
    // } 

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
