// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/PullPayment.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract FootwearNFT is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    string private _baseTokenURI;

    constructor() ERC721("Authentic Footwear", "AFNFT") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
    }

    function mintAuthenticationNFT(address to, uint256 tokenId) external onlyRole(MINTER_ROLE) {
        _mint(to, tokenId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = baseURI;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

contract FootwearGovernance is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction
{
    constructor(IVotes _token)
        Governor("Footwear Governance")
        GovernorSettings(1, /* 1 block */ 50400, /* 1 week */ 0)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4)
    {}

    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }
}

contract Footwears is ReentrancyGuard, Pausable, AccessControl, PullPayment {
    using Counters for Counters.Counter;
    using Address for address payable;

    // Constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant AUTHENTICATOR_ROLE = keccak256("AUTHENTICATOR_ROLE");

    uint256 private constant MAX_RATING = 5;
    uint256 private constant MIN_RATING = 1;
    uint256 private constant MAX_DESCRIPTION_LENGTH = 1000;
    uint256 private constant PLATFORM_FEE_PERCENTAGE = 25; // 2.5%
    uint256 private constant PERCENTAGE_BASE = 1000;
    uint256 private constant RATE_LIMIT_PERIOD = 1 hours;
    uint256 private constant MAX_BULK_OPERATIONS = 50;
    uint256 private constant ESCROW_PERIOD = 7 days;

    // State variables
    Counters.Counter private _sneakerIds;
    address private immutable platformWallet;
    AggregatorV3Interface private immutable ethUsdPriceFeed;
    FootwearNFT private immutable nftContract;
    mapping(address => uint256) private lastActionTimestamp;

    // Optimized structs
    struct CompactSneaker {
        address payable owner;
        uint40 lastPriceUpdate;
        uint16 likesCount;
        uint8 reviewCount;
        bool isActive;
        bool isAuthenticated;
        uint256 price;
        string image;
        string name;
        string description;
        SneakerMetadata metadata;
    }

    struct SneakerMetadata {
        string brand;
        string model;
        string size;
        string condition;
        uint40 manufactureDate;
        string[] images;
    }

    struct Review {
        address reviewer;
        uint8 rating;
        string comment;
        uint40 timestamp;
    }

    struct Escrow {
        uint256 amount;
        uint40 releaseTime;
        bool isDisputed;
        bool isReleased;
    }

    struct Shipment {
        address buyer;
        string shippingAddress;
        bool isDelivered;
        uint40 purchaseDate;
        bool isDisputed;
    }

    // Storage
    mapping(uint256 => CompactSneaker) private sneakers;
    mapping(uint256 => mapping(address => bool)) private sneakerLikes;
    mapping(uint256 => mapping(address => bool)) private sneakerPurchases;
    mapping(uint256 => Review[]) private sneakerReviews;
    mapping(uint256 => Shipment) private shipments;
    mapping(uint256 => Escrow) private escrows;
    mapping(address => uint256[]) private userSneakers;
    mapping(uint256 => uint256[]) private priceHistory;

    // Events
    event SneakerListed(uint256 indexed sneakerId, address indexed seller, uint256 price);
    event SneakerSold(uint256 indexed sneakerId, address indexed seller, address indexed buyer, uint256 price);
    event SneakerAuthenticated(uint256 indexed sneakerId, address indexed authenticator);
    event PriceUpdated(uint256 indexed sneakerId, uint256 oldPrice, uint256 newPrice, uint256 timestamp);
    event ReviewAdded(uint256 indexed sneakerId, address indexed reviewer, uint8 rating);
    event ShipmentUpdated(uint256 indexed sneakerId, bool isDelivered);
    event DisputeRaised(uint256 indexed sneakerId, address indexed buyer);
    event DisputeResolved(uint256 indexed sneakerId, address indexed winner);
    event EscrowCreated(uint256 indexed sneakerId, uint256 amount, uint256 releaseTime);
    event EscrowReleased(uint256 indexed sneakerId, address indexed beneficiary, uint256 amount);

    constructor(
        address _platformWallet,
        address _priceFeed,
        address _nftContract
    ) {
        require(_platformWallet != address(0), "Invalid platform wallet");
        require(_priceFeed != address(0), "Invalid price feed");
        require(_nftContract != address(0), "Invalid NFT contract");

        platformWallet = _platformWallet;
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeed);
        nftContract = FootwearNFT(_nftContract);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(MODERATOR_ROLE, msg.sender);
        _setupRole(AUTHENTICATOR_ROLE, msg.sender);
    }

    // Modifiers
    modifier rateLimit() {
        require(
            block.timestamp >= lastActionTimestamp[msg.sender] + RATE_LIMIT_PERIOD,
            "Rate limit exceeded"
        );
        lastActionTimestamp[msg.sender] = block.timestamp;
        _;
    }

    modifier validateMetadata(SneakerMetadata memory metadata) {
        require(bytes(metadata.brand).length > 0, "Brand required");
        require(bytes(metadata.model).length > 0, "Model required");
        require(bytes(metadata.size).length > 0, "Size required");
        require(metadata.manufactureDate > 0, "Invalid date");
        require(metadata.images.length <= 10, "Too many images");
        _;
    }

    // Main functions

    function batchListSneakers(
        string[] memory _images,
        string[] memory _names,
        string[] memory _descriptions,
        uint256[] memory _prices,
        SneakerMetadata[] memory _metadata
    ) external whenNotPaused nonReentrant rateLimit {
        require(
            _images.length == _names.length &&
            _names.length == _descriptions.length &&
            _descriptions.length == _prices.length &&
            _prices.length == _metadata.length,
            "Arrays length mismatch"
        );
        require(_images.length <= MAX_BULK_OPERATIONS, "Batch too large");

        for(uint i = 0; i < _images.length; i++) {
            _listSneaker(_images[i], _names[i], _descriptions[i], _prices[i], _metadata[i]);
        }
    }

    function _listSneaker(
        string memory _image,
        string memory _name,
        string memory _description,
        uint256 _price,
        SneakerMetadata memory _metadata
    ) private validateMetadata(_metadata) {
        require(bytes(_name).length > 0, "Name required");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        require(_price > 0, "Invalid price");

        uint256 sneakerId = _sneakerIds.current();
        CompactSneaker storage newSneaker = sneakers[sneakerId];

        newSneaker.owner = payable(msg.sender);
        newSneaker.image = _image;
        newSneaker.name = _name;
        newSneaker.description = _description;
        newSneaker.price = _price;
        newSneaker.isActive = true;
        newSneaker.lastPriceUpdate = uint40(block.timestamp);
        newSneaker.metadata = _metadata;

        userSneakers[msg.sender].push(sneakerId);
        priceHistory[sneakerId].push(_price);
        _sneakerIds.increment();

        emit SneakerListed(sneakerId, msg.sender, _price);
    }

    function purchaseSneaker(
        uint256 sneakerId,
        string memory shippingAddress
    ) external payable whenNotPaused nonReentrant rateLimit {
        CompactSneaker storage sneaker = sneakers[sneakerId];
        require(sneaker.isActive, "Sneaker not active");
        require(msg.sender != sneaker.owner, "Cannot buy own sneaker");
        require(!sneakerPurchases[sneakerId][msg.sender], "Already purchased");
        require(msg.value >= sneaker.price, "Insufficient payment");

        // Create escrow
        escrows[sneakerId] = Escrow({
            amount: sneaker.price,
            releaseTime: uint40(block.timestamp + ESCROW_PERIOD),
            isDisputed: false,
            isReleased: false
        });

        // Update state
        sneakerPurchases[sneakerId][msg.sender] = true;
        address payable previousOwner = sneaker.owner;
        sneaker.owner = payable(msg.sender);

        // Create shipment
        shipments[sneakerId] = Shipment({
            buyer: msg.sender,
            shippingAddress: shippingAddress,
            isDelivered: false,
            purchaseDate: uint40(block.timestamp),
            isDisputed: false
        });

        emit SneakerSold(sneakerId, previousOwner, msg.sender, sneaker.price);
        emit EscrowCreated(sneakerId, sneaker.price, block.timestamp + ESCROW_PERIOD);

        // Refund excess payment
        if (msg.value > sneaker.price) {
            payable(msg.sender).sendValue(msg.value - sneaker.price);
        }
    }

    function releaseEscrow(uint256 sneakerId) external nonReentrant {
        Escrow storage escrow = escrows[sneakerId];
        require(!escrow.isReleased, "Already released");
        require(!escrow.isDisputed, "Disputed");
        require(
            msg.sender == shipments[sneakerId].buyer ||
            block.timestamp >= escrow.releaseTime,
            "Not authorized"
        );

        CompactSneaker storage sneaker = sneakers[sneakerId];
        uint256 platformFee = (escrow.amount * PLATFORM_FEE_PERCENTAGE) / PERCENTAGE_BASE;
        uint256 sellerAmount = escrow.amount - platformFee;

        escrow.isReleased = true;
        _asyncTransfer(platformWallet, platformFee);
        _asyncTransfer(payable(sneaker.owner), sellerAmount);

        emit EscrowReleased(sneakerId, sneaker.owner, sellerAmount);
    }

    function authenticateSneaker(uint256 sneakerId) external onlyRole(AUTHENTICATOR_ROLE) {
        CompactSneaker storage sneaker = sneakers[sneakerId];
        require(!sneaker.isAuthenticated, "Already authenticated");

        sneaker.isAuthenticated = true;
        nftContract.mintAuthenticationNFT(sneaker.owner, sneakerId);

        emit SneakerAuthenticated(sneakerId, msg.sender);
    }
