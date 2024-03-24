// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OrcsToken is ERC20 {

    address public immutable GOVERNOR;
    
    event BatchTransfer(address[] recipients, uint256[] amounts);
    event TokensPurchased(address indexed buyer, uint256 amount);
    event ETHWithdrawn(address recipient, uint256 amount);
    event ERC20Withdrawn(address recipient, address token, uint256 amount);

    error OrcsToken__OnlyGovernor();
    error OrcsToken__BatchTransferArrayMismatch();
    error OrcsToken__TransferFailed();
    error OrcsToken__NotEnoughTokensToRedeem();
    error OrcsToken__RedeemValueAlreadySet();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert OrcsToken__OnlyGovernor();
        _;
    }

    constructor(address _governor) ERC20("$Orcs", "$ORCS") {
        GOVERNOR = _governor;
    }

    fallback() external payable {}
    receive() external payable {}

    function batchTransfer(address[] calldata _recipients, uint256[] calldata _amounts) external onlyGovernor {
        if (_recipients.length != _amounts.length) revert OrcsToken__BatchTransferArrayMismatch();
        for (uint i; i < _recipients.length; ++i) {
            _mint(_recipients[i], _amounts[i]);
        }
        emit BatchTransfer(_recipients, _amounts);
    }

    function purchaseTokens() external payable {
        require(msg.value > 0);
        _mint(msg.sender, msg.value);
        emit TokensPurchased(msg.sender, msg.value);
    }

    function withdrawETH(address _recipient, uint256 _amount) external onlyGovernor {
        (bool success, ) = _recipient.call{value: _amount}("");
        if (!success) revert OrcsToken__TransferFailed();
        emit ETHWithdrawn(_recipient, _amount);
    }

}