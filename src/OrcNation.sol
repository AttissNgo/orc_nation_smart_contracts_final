// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
// import "solmate/src/utils/LibString.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "chainlink/VRFCoordinatorV2Interface.sol";
import "chainlink/VRFConsumerBaseV2.sol";
// import "@openzeppelin/contracts/utils/Counters.sol";
import "./Interfaces/IRaffle.sol";
import "./Interfaces/IPricefeed.sol";
import "./Interfaces/IGovernor.sol";

contract OrcNation is ERC721Enumerable, VRFConsumerBaseV2 {
    // using Counters for Counters.Counter;
    // using LibString for uint256;
    using Strings for uint256;
    
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;
    IPricefeed public immutable PRICEFEED;
    IRaffle public immutable RAFFLE;
    address public immutable PAYMENT_SPLITTER;
    address public immutable GOVERNOR;

    // uint256 public constant PRICE_IN_USD = 65;
    uint256 public PRICE_IN_USD = 65; // can be set by governor action
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant MAX_WHITELISTEES = 500;
    uint256 public constant MAX_PRESALE_MINTS = 3;
    uint256 public constant MAX_COMP_MINTS = 50;
    uint256 public constant MAX_MINTS_PER_TX = 10;

    uint256 public immutable PRESALE;
    uint256 public immutable SALE_OPEN;

    uint96 public constant ROYALTY_BASIS_POINTS = 500;
    address private royaltyReceiver;
    string private baseUri; 

    // Counters.Counter private tokenIds;
    uint256 private tokenIds;
    uint256 public remainingUris = MAX_SUPPLY;
    mapping(uint256 => uint256[]) private requestIdToTokenIds; // VRF request ID => batch of token Ids
    mapping(uint256 => uint256) private availableUris;
    mapping(uint256 => uint256) public tokenIdToUriExtension;

    uint16 whitelistCounter; // tracks number of addresses assigned to whitelist
    uint8 compMintCounter; // tracks number of addresses assign a comp mint
    mapping(address => bool) private whitelist;
    // Counters.Counter private whitelistCounter;
    // Counters.Counter private compMintCounter;
    mapping(address => bool) private compMintRecipient;
    mapping(address => bool) private compMintClaimed; 

    // tracks buyers for raffle
    address[] private buyers;
    mapping(address => bool) public isBuyer;

    // VRF config
    bytes32 public keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
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
    error OrcNation__RaffleNotComplete();
    error OrcNation__MustMintAtLeastOneToken();
    error OrcNation__MaxMintsPerTransactionExceeded();
    error OrcNation__OnlyGovernor();
    error OrcNation__OnlyRaffle();
    error OrcNation__OnlyAdmin();
    error OrcNation__InvalidNewPrice();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert OrcNation__OnlyGovernor();
        _;
    }

    modifier onlyAdmin() {
        if(!IGovernor(GOVERNOR).isAdmin(msg.sender)) revert OrcNation__OnlyAdmin();
        _;
    }

    constructor(
        address _vrfCoordinatorV2,
        address _priceFeed,
        address _governor,
        address _paymentSplitter,
        address _computedRaffleAddress,
        // address _royaltyReceiver,
        address _initialMintRecipient,
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
        // royaltyReceiver = _royaltyReceiver;
        royaltyReceiver = msg.sender;
        baseUri = _baseUri;
        PRESALE = _presale;
        SALE_OPEN = _saleOpen;
        subscriptionId = _subscriptionId;
        RAFFLE = IRaffle(_computedRaffleAddress);

        // 500 mints on deployement
        _initialMint(_initialMintRecipient);
    }

    function reducePrice(uint256 _newPriceInUSD) external onlyGovernor {
        if(_newPriceInUSD < 32 || _newPriceInUSD > 97) revert OrcNation__InvalidNewPrice();
        PRICE_IN_USD = _newPriceInUSD;
        emit TokenPriceChanged(_newPriceInUSD);
    }

    ///////////////////
    ///   MINTING   ///
    ///////////////////

    function mint(address _to, uint256 _numberOfTokens) external payable returns (uint256) {
        if(!isMintingOpen()) revert OrcNation__MintingNotOpen();
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
        addToRaffle(_to);
        // CHANGED from 'price' to msg.value so Orc Nation never holds money (in case someone overpays)
        (bool success, ) = PAYMENT_SPLITTER.call{value: msg.value}(""); // should this be changed to a named function??
        require(success, "Payment transfer failed");

        uint256 requestId = _mintTokens(_to, _numberOfTokens);
        return requestId;
    }

    function mintComp() external returns (uint256) {
        if(!isMintingOpen()) revert OrcNation__MintingNotOpen();
        if(!isCompMintRecipient(msg.sender)) revert OrcNation__NotEligibleForCompMint();
        if(compMintClaimed[msg.sender]) revert OrcNation__CompMintAlreadyClaimed();
        _checkSupply(1);
        compMintClaimed[msg.sender] = true;
        uint256 requestId = _mintTokens(msg.sender, 1); 
        return requestId;
    }

    function _mintTokens(address _to, uint256 _numberOfTokens) private returns (uint256) {
        uint256 requestId = _createVrfRequest();
        uint256[] memory batchTokens =  new uint256[](_numberOfTokens);
        for(uint i; i < _numberOfTokens; ++i) {
            // tokenIds.increment();
            ++tokenIds;
            // uint256 newTokenId = tokenIds.current();
            // uint256 newTokenId = tokenIds;
            _mint(_to, tokenIds); 
            batchTokens[i] = tokenIds;
        }
        requestIdToTokenIds[requestId] = batchTokens;
        _handleRaffle();
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

    function _initialMint(address _recipient) private {
        uint256 updatedRemainingUris = remainingUris;
        for(uint i = 1; i <= 500; ) {
            ++tokenIds;
            _mint(_recipient, tokenIds);
            uint256 index = uint256(keccak256(abi.encodePacked(block.timestamp, i))) % updatedRemainingUris;
            uint256 uriExt = _getAvailableUriAtIndex(index, updatedRemainingUris);
            tokenIdToUriExtension[i] = uriExt;
            --updatedRemainingUris;
            unchecked {++i;}
        }
    }

    function isMintingOpen() public view returns (bool) {
        return block.timestamp >= PRESALE;
    }

    function _checkSupply(uint256 _numberOfTokens) private view {
        // if(tokenIds.current() + _numberOfTokens > MAX_SUPPLY) revert OrcNation__WillExceedMaxSupply();
        if(tokenIds + _numberOfTokens > MAX_SUPPLY) revert OrcNation__WillExceedMaxSupply();
    }

    function calculatePrice(uint256 _numberOfTokens) public view returns (uint256) {
        uint256 price = getPriceInMATIC() * _numberOfTokens;
        if(block.timestamp >= PRESALE && block.timestamp < SALE_OPEN) {
            price = (price * 85)/100;
        }
        return price;

        // MUMBAI TEST PRICE
        // return price/100000;
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
        // if(!IGovernor(GOVERNOR).isAdmin(msg.sender)) revert OrcNation__OnlyAdmin();
        if(whitelistCounter + _whitelistees.length > MAX_WHITELISTEES) {
            revert OrcNation__WillExceedMaxWhitelistees();
        }
        for(uint i = 0; i < _whitelistees.length; ++i) {
            ++whitelistCounter;
            whitelist[_whitelistees[i]] = true;
        }
    }

    function assignCompMint(address _recipient) external onlyAdmin {
        // if(!IGovernor(GOVERNOR).isAdmin(msg.sender)) revert OrcNation__OnlyAdmin();
        ++compMintCounter;
        if(compMintCounter > MAX_COMP_MINTS) revert OrcNation__MaxCompMintsExceeded();
        if(compMintClaimed[_recipient]) revert OrcNation__CompMintAlreadyClaimed();
        if(isCompMintRecipient(_recipient)) revert OrcNation__CompMintAlreadyAssignedToAddress();
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

    function _handleRaffle() private {
        // uint256 numMinted = tokenIds.current();
        if(tokenIds < 2000) return;
        uint256 tokenThreshold;
        if(tokenIds >= 2000 && tokenIds < 4000) tokenThreshold = 2000;
        else if (tokenIds >= 4000 && tokenIds < 6000) tokenThreshold = 4000;
        else if (tokenIds >= 6000 && tokenIds != 10000) tokenThreshold = 6000;
        else if (tokenIds == 10000) tokenThreshold = 10000;
        if(RAFFLE.raffleDrawn(tokenThreshold)) return;
        else RAFFLE.drawRaffle(tokenThreshold); 
    }

    function addToRaffle(address _buyer) internal {
        if(!isBuyer[_buyer]) {
            buyers.push(_buyer);
            isBuyer[_buyer] = true;
        }
    }

    function addRaffle2000Winners(address[] calldata _winners) external {
        if(msg.sender != address(RAFFLE)) revert OrcNation__OnlyRaffle();
        for(uint i = 0; i < _winners.length; ++i) {
            compMintRecipient[_winners[i]] = true;
            if(compMintClaimed[_winners[i]]) compMintClaimed[_winners[i]] = false;
        }
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
        // return tokenIds.current();
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
        // return whitelistCounter.current();
    }

    function getCompMintCount() public view returns (uint256) {
        return compMintCounter;
        // return compMintCounter.current();
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

    // function getVRFConfig() external view returns(bytes32, uint64, uint16, uint32, uint32) {
    //     return(
    //         keyHash, 
    //         subscriptionId, 
    //         requestConfirmations, 
    //         callbackGasLimit, 
    //         numWords
    //     );
    // }

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
