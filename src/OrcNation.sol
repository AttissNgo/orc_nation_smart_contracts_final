// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "chainlink/VRFCoordinatorV2Interface.sol";
import "chainlink/VRFConsumerBaseV2.sol";
import "./interfaces/IPricefeed.sol";
import "./interfaces/IGovernor.sol";

contract OrcNation is  VRFConsumerBaseV2, ERC721Enumerable {
    using Strings for uint256;
    
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;
    IPricefeed public immutable PRICEFEED;
    address public immutable PAYMENT_SPLITTER;
    address public immutable GOVERNOR;

    uint256 public PRICE_IN_USD = 65; // can be set by governor action
    uint16 public constant MAX_SUPPLY = 10000;
    uint16 public constant MAX_WHITELISTEES = 500;
    uint8 public constant MAX_PRESALE_MINTS = 3;
    uint8 public constant MAX_COMP_MINTS = 50; 
    uint8 public constant MAX_RAFFLE_MINTS = 5;
    uint8 public constant MAX_MINTS_PER_TX = 10;
    uint16 public constant MAX_OWNER_MINTS = 500;


    uint16 public whitelistCounter; 
    uint8 public compMintCounter; 
    uint256 public ownerMintCounter;

    uint256 public immutable PRESALE;
    uint256 public immutable SALE_OPEN;

    uint96 public constant ROYALTY_BASIS_POINTS = 500;
    address private royaltyReceiver;
    string private baseUri;

    uint256 private tokenIds;
    uint256 public remainingUris = MAX_SUPPLY;
    mapping(uint256 => uint256[]) private requestIdToTokenIds; // VRF request ID => batch of token Ids
    mapping(uint256 => uint256) private availableUris;
    mapping(uint256 => uint256) public tokenIdToUriExtension;

    mapping(address => bool) private whitelist;
    mapping(address => bool) private compMintRecipient;
    mapping(address => bool) private compMintClaimed; 

    // raffle
    address[] private buyers;
    mapping(address => bool) public isBuyer;
    bool public raffleWinnersAdded;
    mapping(address => bool) public canMintRaffle;

    // VRF config
    bytes32 public keyHash = 0xcc294a196eeeb44da2888d17c0625cc88d70d9760a69d58d853ba6581a9ab0cd;
    uint64 public subscriptionId;
    uint16 public requestConfirmations = 3;
    uint32 public callbackGasLimit = 1000000;
    uint32 public numWords = 1;

    event VRFRequestCreated(uint256 requestId);
    event RoyaltyReceiverChanged(address newReceiver);
    event RaffleWinnersAdded(address[] winners);
    event TokenPriceChanged(uint256 newPrice);

    error OrcNation__InvalidSaleTime();
    error OrcNation__TokenDoesNotExist();
    error OrcNation__PriceFeedAnswerNegative();
    error OrcNation__WillExceedMaxWhitelistees();
    error OrcNation__MaxCompMintsExceeded();
    error OrcNation__CompMintAlreadyClaimed();
    error OrcNation__CompMintAlreadyAssignedToAddress();
    error OrcNation__MaxThreePresaleMintsPerWhitelistedAddress();
    error OrcNation__MintingNotOpen();
    error OrcNation__NotWhitelisted();
    error OrcNation__InsufficientPayment(uint256 paymentDue);
    error OrcNation__WillExceedMaxSupply();
    error OrcNation__NotEligibleForCompMint();
    error OrcNation__MustMintAtLeastOneToken();
    error OrcNation__MaxMintsPerTransactionExceeded();
    error OrcNation__OnlyGovernor();
    error OrcNation__OnlyAdmin();
    error OrcNation__InvalidNewPrice();
    error OrcNation__WillExceedMaxOwnerMints();
    error OrcNation__RaffleWinnersAlreadyAdded();
    error OrcNation__MaxRaffleWinnersExceeded();
    error OrcNation__NotEligibleForRaffleMint();
    error OrcNation__RaffleOnlyAfter2000Tokens();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert OrcNation__OnlyGovernor();
        _;
    }

    modifier onlyAdmin() {
        if(!IGovernor(GOVERNOR).isAdmin(msg.sender)) revert OrcNation__OnlyAdmin();
        _;
    }

    modifier onlyDuringMinting() {
        if(!isMintingOpen()) revert OrcNation__MintingNotOpen();
        _;
    }

    constructor(
        address _vrfCoordinatorV2,
        address _priceFeed,
        address _governor,
        address _paymentSplitter,
        address _royaltyReceiver,
        uint256 _presale,
        uint256 _saleOpen,
        uint64 _subscriptionId,
        string memory _baseUri
    ) 
        ERC721("OrcNation", "ORCS")
        VRFConsumerBaseV2(_vrfCoordinatorV2)
    {
        if(_presale < block.timestamp || _saleOpen < _presale) revert OrcNation__InvalidSaleTime();
        VRF_COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinatorV2);
        PRICEFEED = IPricefeed(_priceFeed);
        GOVERNOR = _governor;
        PAYMENT_SPLITTER = _paymentSplitter;
        royaltyReceiver = _royaltyReceiver;
        baseUri = _baseUri;
        PRESALE = _presale;
        SALE_OPEN = _saleOpen;
        subscriptionId = _subscriptionId;
    }

    function setTokenPrice(uint256 _newPriceInUSD) external onlyGovernor {
        if(_newPriceInUSD < 32 || _newPriceInUSD > 97) revert OrcNation__InvalidNewPrice();
        PRICE_IN_USD = _newPriceInUSD;
        emit TokenPriceChanged(_newPriceInUSD);
    }

    ///////////////////
    ///   MINTING   ///
    ///////////////////

    function mint(
        address _to, 
        uint256 _numberOfTokens
    ) 
        external payable onlyDuringMinting returns (uint256) 
    {
        if(block.timestamp >= PRESALE && block.timestamp < SALE_OPEN) {
            if(!isWhitelisted(_to)) revert OrcNation__NotWhitelisted();
            if(balanceOf(_to) + _numberOfTokens > MAX_PRESALE_MINTS) {
                revert OrcNation__MaxThreePresaleMintsPerWhitelistedAddress();
            }
        }
        if(_numberOfTokens < 1) revert OrcNation__MustMintAtLeastOneToken();
        if(_numberOfTokens > MAX_MINTS_PER_TX) revert OrcNation__MaxMintsPerTransactionExceeded();

        _checkSupply(_numberOfTokens);

        uint256 price = calculatePrice(_numberOfTokens);
        if(msg.value < price) revert OrcNation__InsufficientPayment(price);
        (bool success, ) = PAYMENT_SPLITTER.call{value: msg.value}(""); 
        require(success, "Payment transfer failed");
        addToRaffle(_to);

        uint256 requestId = _mintTokens(_to, _numberOfTokens);
        return requestId;
    }

    function mintComp() external onlyDuringMinting returns (uint256) {
        if(!isCompMintRecipient(msg.sender)) revert OrcNation__NotEligibleForCompMint();
        if(compMintClaimed[msg.sender]) revert OrcNation__CompMintAlreadyClaimed();
        _checkSupply(1);
        compMintClaimed[msg.sender] = true;
        uint256 requestId = _mintTokens(msg.sender, 1); 
        return requestId;
    }

    function mintRaffle() external onlyDuringMinting returns (uint256) {
        if(!canMintRaffle[msg.sender]) revert OrcNation__NotEligibleForRaffleMint();
        _checkSupply(1);
        canMintRaffle[msg.sender] = false;
        uint256 requestId = _mintTokens(msg.sender, 1); 
        return requestId;
    }

    function _mintTokens(address _to, uint256 _numberOfTokens) private returns (uint256) {
        uint256 requestId = _createVrfRequest();
        uint256[] memory batchTokens =  new uint256[](_numberOfTokens);
        for(uint i; i < _numberOfTokens; ++i) {
            ++tokenIds;
            _mint(_to, tokenIds); 
            batchTokens[i] = tokenIds;
        }
        requestIdToTokenIds[requestId] = batchTokens;
        return requestId;
    }

    function _createVrfRequest() private returns (uint256 requestId) {
        requestId = VRF_COORDINATOR.requestRandomWords(
            keyHash, 
            subscriptionId, 
            requestConfirmations, 
            callbackGasLimit, 
            numWords
        ); 
        emit VRFRequestCreated(requestId);
    }

    function fulfillRandomWords(
        uint256 requestId, 
        uint256[] memory randomWords
    ) 
        internal override
    {
        uint256 updatedRemainingUris = remainingUris;
        for(uint i; i < requestIdToTokenIds[requestId].length; ) {
            uint256 index = uint256(keccak256(abi.encodePacked(randomWords[0], i))) % updatedRemainingUris;
            uint256 uriExt = _getAvailableUriAtIndex(index, updatedRemainingUris);
            tokenIdToUriExtension[requestIdToTokenIds[requestId][i]] = uriExt;
            --updatedRemainingUris;
            unchecked {++i;}
        }
        remainingUris = updatedRemainingUris;
    }

    function ownerMint(uint256 _numberOfTokens) external onlyAdmin returns (uint256 requestId) {
        if(_numberOfTokens < 1) revert OrcNation__MustMintAtLeastOneToken();
        if(_numberOfTokens + ownerMintCounter > MAX_OWNER_MINTS) revert OrcNation__WillExceedMaxOwnerMints();
        if(_numberOfTokens > MAX_MINTS_PER_TX) revert OrcNation__MaxMintsPerTransactionExceeded();
        _checkSupply(_numberOfTokens);
        ownerMintCounter += _numberOfTokens;
        requestId = _mintTokens(msg.sender, _numberOfTokens); 
    }  

    function _getAvailableUriAtIndex(uint256 _index, uint256 _updatedNumAvailableUris)
        private
        returns (uint256)
    {
        uint256 valueAtIndex = availableUris[_index]; 
        uint256 lastIndex = _updatedNumAvailableUris - 1; 
        uint256 lastValueInMapping = availableUris[lastIndex]; 
        uint256 result = valueAtIndex == 0 ? _index : valueAtIndex; 
        if(_index != lastIndex) {
            availableUris[_index] = lastValueInMapping == 0 ? lastIndex : lastValueInMapping; 
        }
        if(lastValueInMapping != 0) { 
            delete availableUris[lastIndex];
        }
        return result;
    }

    function isMintingOpen() public view returns (bool) {
        return block.timestamp >= PRESALE;
    }

    function _checkSupply(uint256 _numberOfTokens) private view {
        if(tokenIds + _numberOfTokens > MAX_SUPPLY) revert OrcNation__WillExceedMaxSupply();
    }

    function calculatePrice(uint256 _numberOfTokens) public view returns (uint256) {
        uint256 price = getPriceInMATIC() * _numberOfTokens;
        if(block.timestamp >= PRESALE && block.timestamp < SALE_OPEN) {
            price = (price * 85)/100;
        }
        return price;
    }

    function getPriceInMATIC() public view returns (uint256) {
        (,int price,,,) = PRICEFEED.latestRoundData();
        if(price < 0) revert OrcNation__PriceFeedAnswerNegative();
        int256 decimals = int256(10 ** PRICEFEED.decimals());
        int256 usdPriceDecimals = int256(PRICE_IN_USD * 1e18);
        return uint256(usdPriceDecimals / price * decimals);
    }

    /////////////////////////////
    ///   WHITELIST & COMPS   ///
    /////////////////////////////

    function addToWhitelist(address[] calldata _whitelistees) external onlyAdmin {
        if(whitelistCounter + _whitelistees.length > MAX_WHITELISTEES) revert OrcNation__WillExceedMaxWhitelistees();
        for(uint i = 0; i < _whitelistees.length; ++i) {
            ++whitelistCounter;
            whitelist[_whitelistees[i]] = true;
        }
    }

    function assignCompMint(address _recipient) external onlyAdmin {
        if(isCompMintRecipient(_recipient)) revert OrcNation__CompMintAlreadyAssignedToAddress();
        if(compMintCounter + 1 > MAX_COMP_MINTS) revert OrcNation__MaxCompMintsExceeded();
        ++compMintCounter;
        compMintRecipient[_recipient] = true;
    }

    function isWhitelisted(address user) public view returns (bool) {
        return whitelist[user];
    }

    function isCompMintRecipient(address user) public view returns (bool) {
        return compMintRecipient[user];
    }

    function hasClaimedCompMint(address user) public view returns (bool) {
        return compMintClaimed[user];
    }
    
    //////////////////
    ///   RAFFLE   ///
    //////////////////

    function addToRaffle(address _buyer) internal {
        if(!isBuyer[_buyer]) {
            buyers.push(_buyer);
            isBuyer[_buyer] = true;
        }
    }

    function addRaffle2000Winners(address[] calldata _winners) external onlyGovernor {
        if(getCurrentTokenId() < 2000) revert OrcNation__RaffleOnlyAfter2000Tokens();
        if(_winners.length > MAX_RAFFLE_MINTS) revert OrcNation__MaxRaffleWinnersExceeded();
        if(raffleWinnersAdded) revert OrcNation__RaffleWinnersAlreadyAdded();
        for(uint i = 0; i < _winners.length; ++i) {
            canMintRaffle[_winners[i]] = true;
        }
        raffleWinnersAdded = true;
        emit RaffleWinnersAdded(_winners);
    }

    ///////////////
    ///   URI   ///
    ///////////////

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        if(ownerOf(_tokenId) == address(0)) revert OrcNation__TokenDoesNotExist();
        return string.concat(baseUri, tokenIdToUriExtension[_tokenId].toString(), ".json");
    }

    ///////////////////
    ///   ROYALTY   ///
    ///////////////////

    // ROYALTY AS PER ERC-2981
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) 
        external 
        view 
        returns (address receiver, uint256 royaltyAmount)
    {
        require(ownerOf(_tokenId) != address(0));
        return(royaltyReceiver, (_salePrice * ROYALTY_BASIS_POINTS) / 10000);
    }

    function setRoyaltyReceiver(address _newReceiver) external onlyGovernor {
        require(_newReceiver != address(0));
        royaltyReceiver = _newReceiver;
        emit RoyaltyReceiverChanged(_newReceiver);
    }

    ///////////////////
    ///   GETTERS   ///
    ///////////////////

    function getCurrentTokenId() public view returns (uint256) {
        return tokenIds;
    }

    function getBatchTokens(uint256 _requestId) public view returns (uint256[] memory) {
        return requestIdToTokenIds[_requestId];
    }

    function getBaseUri() external view returns (string memory) {
        return baseUri;
    }

    function getRoyaltyReceiver() public view returns (address) {
        return royaltyReceiver;
    }

    function getWhitelistCount() public view returns (uint256) {
        return whitelistCounter;
    }

    function getCompMintCount() public view returns (uint256) {
        return compMintCounter;
    }

    function getBuyers() public view returns (address[] memory) {
        return buyers;
    } 

    function totalNumberOfBuyers() public view returns (uint256) {
        return buyers.length;
    }

    function getBuyerByIndex(uint256 index) public view returns (address) {
        return buyers[index];
    }

    /////////////////////////////
    ///   INTERFACE SUPPORT   ///
    /////////////////////////////

    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual
        override(ERC721Enumerable) 
        returns (bool) 
    {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x2a55205a; //ERC2981
    }


}
