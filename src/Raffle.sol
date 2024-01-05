// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "chainlink/VRFCoordinatorV2Interface.sol";
import "chainlink/VRFConsumerBaseV2.sol";
import "./Interfaces/IOrcNation.sol";
import "./Interfaces/IGovernor.sol";

interface IPaymentSplitter {
    function getPayees() external view returns (address[] memory);
    function isPayee(address) external view returns (bool);
}

contract Raffle is VRFConsumerBaseV2 {
    
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;
    IPaymentSplitter public immutable PAYMENT_SPLITTER;
    IOrcNation public immutable ORC_NATION;
    IGovernor public immutable GOVERNOR;

    bytes32 private keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
    uint64 private subscriptionId;
    uint16 private requestConfirmations = 3;
    uint32 private callbackGasLimit = 600000;
    uint32 private numWords = 1; 

    mapping(uint256 => bool) public raffleDrawn;
    mapping(uint256 => bool) public raffleComplete;
    mapping(uint256 => uint256) public requestIds;
    mapping(uint256 => address[]) private raffleWinners;
    mapping(address => bool) public isRaffleWinner;
    mapping(address => uint256) private raffleWinnings;
    mapping(address => bool) private winningsClaimed;

    event RaffleDrawn(uint256 tokenThreshold, uint256 requestId);
    event RaffleWinnersSelected(uint256 tokenThreshold, address[] winners);
    event RafflePrizeAmountReceived(uint256 tokenThreshold, uint256 prizeAmount);
    event WinningsClaimed(address winner, uint256 amount);

    error Raffle__RaffleAlreadyDrawn();
    error Raffle__NotEnoughTokensSold();
    error Raffle__NotPaymentSplitter();
    error Raffle__NotRaffleWinner();
    error Raffle__WinningsAlreadyClaimed();

    error Raffle__OnlyOrcNation();
    error Raffle__PrizeMismatch();
    error Raffle__InsufficientPrizeTransfer();

    modifier onlyOrcNation {
        if(msg.sender != address(ORC_NATION)) revert Raffle__OnlyOrcNation();
        _;
    }

    constructor(
        address _vrfCoordinatorV2, 
        uint64 _subscriptionId,
        address _orcNation,
        address _paymentSplitter,
        address _governor
    ) 
        VRFConsumerBaseV2(_vrfCoordinatorV2) 
    {
        VRF_COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinatorV2);
        subscriptionId = _subscriptionId;
        ORC_NATION = IOrcNation(_orcNation);
        PAYMENT_SPLITTER = IPaymentSplitter(_paymentSplitter);
        GOVERNOR = IGovernor(_governor);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        if(requestId == requestIds[2000]) _selectRaffleWinners(randomWords[0], 2000, 5);
        else if(requestId == requestIds[4000]) _selectRaffleWinners(randomWords[0], 4000, 3);
        else if(requestId == requestIds[6000]) _selectRaffleWinners(randomWords[0], 6000, 1);
        else if(requestId == requestIds[10000]) _selectRaffleWinners(randomWords[0], 10000, 1);
    }

    function drawRaffle(uint256 _tokenThreshold) external onlyOrcNation {
        if(raffleDrawn[_tokenThreshold]) revert Raffle__RaffleAlreadyDrawn();
        if(ORC_NATION.getCurrentTokenId() < _tokenThreshold) revert Raffle__NotEnoughTokensSold();
        uint256 requestId = VRF_COORDINATOR.requestRandomWords(
            keyHash, 
            subscriptionId, 
            requestConfirmations, 
            callbackGasLimit, 
            numWords
        );
        requestIds[_tokenThreshold] = requestId;
        raffleDrawn[_tokenThreshold] = true;
        emit RaffleDrawn(_tokenThreshold, requestId);
    }

    function _selectRaffleWinners(
        uint256 _randomWord, 
        uint256 _tokenThreshold, 
        uint256 _numWinners
    ) 
        private 
    {
        uint256 nonce;
        uint256 numSelected;
        uint256 numEntries = ORC_NATION.totalNumberOfBuyers();
        uint256 winnerIndex;
        address[] memory winners = new address[](_numWinners);
        while(numSelected < _numWinners) {
            winnerIndex = uint256(keccak256(abi.encodePacked(_randomWord, nonce))) % numEntries;
            address winner = ORC_NATION.getBuyerByIndex(winnerIndex);
            if(!isRaffleWinner[winner] && !isTeamMember(winner)) {
                winners[numSelected] = winner;
                isRaffleWinner[winner] = true;
                ++numSelected;
            }
            ++nonce;
        }
        raffleWinners[_tokenThreshold] = winners;
        raffleComplete[_tokenThreshold] = true;
        emit RaffleWinnersSelected(_tokenThreshold, winners);
        if(_tokenThreshold == 2000) {
            ORC_NATION.addRaffle2000Winners(winners);
        }
    }

    function receiveRafflePrize(uint256 _tokenThreshold, uint256[] memory _prizes) external payable {
        if(msg.sender != address(PAYMENT_SPLITTER)) revert Raffle__NotPaymentSplitter();
        if(_prizes.length != raffleWinners[_tokenThreshold].length) revert Raffle__PrizeMismatch();
        uint256 totalPrizeAmount;
        for(uint i = 0; i < raffleWinners[_tokenThreshold].length; ++i) {
            if(raffleWinnings[raffleWinners[_tokenThreshold][i]] == 0) {
                raffleWinnings[raffleWinners[_tokenThreshold][i]] = _prizes[i];
                totalPrizeAmount += _prizes[i];
            }
        }
        if(msg.value != totalPrizeAmount) revert Raffle__InsufficientPrizeTransfer();
        emit RafflePrizeAmountReceived(_tokenThreshold, totalPrizeAmount);
    }

    function claimRaffleWinnings() external {
        uint256 winnings = getRaffleWinnings(msg.sender);
        if(winnings == 0) revert Raffle__NotRaffleWinner();
        if(hasClaimedWinnings(msg.sender)) revert Raffle__WinningsAlreadyClaimed();
        winningsClaimed[msg.sender] = true;
        (bool success, ) = payable(msg.sender).call{value: winnings}("");
        require(success, "transfer failed");
        emit WinningsClaimed(msg.sender, winnings);
    }

    function isTeamMember(address addr) public view returns (bool) {
        return PAYMENT_SPLITTER.isPayee(addr) || GOVERNOR.isAdmin(addr);
    }

    function hasClaimedWinnings(address winner) public view returns (bool) {
        return winningsClaimed[winner];
    }

    function getRaffleWinners(uint256 _tokenThreshold) public view returns (address[] memory) {
        return raffleWinners[_tokenThreshold];
    }

    function getRaffleWinnings(address _winner) public view returns (uint256) {
        return raffleWinnings[_winner];
    }

}