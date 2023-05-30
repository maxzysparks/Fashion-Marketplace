// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface IERC20Token {
    function transfer(address, uint256) external returns (bool);

    function approve(address, uint256) external returns (bool);

    function transferFrom(address, address, uint256) external returns (bool);

    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function allowance(address, address) external view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract Footwears {
    uint private sneakersLength = 0;
    address private cUsdTokenAddress =
        0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;

    event likeSneakerEvent(address indexed userAddress, uint256 index);
    event dislikeSneakerEvent(address indexed userAddress, uint256 index);
    event deleteSneakerEvent(uint256 sneakerId);
    event sellSneakerEvent(
        address indexed seller,
        uint256 index,
        uint256 price
    );

    event buySneakerEvent(
        address indexed seller,
        address indexed buyer,
        uint256 index
    );
    event addSneakerEvent(address indexed owner, uint256 sneakerId);

    struct Sneaker {
        address payable owner;
        string image;
        string name;
        string description;
        uint price;
        uint likesCount;
        Review[] reviews;
    }
    struct Shipment {
        address buyer;
        string shippingAddress;
        bool isDelivered;
    }
    struct Review {
        address reviewer;
        uint256 rating;
        string comment;
    }

    mapping(uint256 => Shipment) private shipments;
    mapping(uint => Sneaker) internal sneakers;
    mapping(uint256 => mapping(address => bool)) likes; // sneakers liked by all users

    function getShipmentStatus(
        uint256 _index
    ) external view returns (bool, string memory) {
        require(_index < sneakersLength, "Invalid index");
        Shipment storage shipment = shipments[_index];
        return (shipment.isDelivered, shipment.shippingAddress);
    }

    function confirmDelivery(uint256 _index) external {
        require(_index < sneakersLength, "Invalid index");
        require(
            shipments[_index].buyer == msg.sender,
            "Only buyer can confirm delivery"
        );
        shipments[_index].isDelivered = true;
    }

    function addReview(
        uint256 _index,
        uint256 _rating,
        string calldata _comment
    ) external {
        require(_index < sneakersLength, "Sneaker does not exist");
        require(_rating >= 1 && _rating <= 5, "Invalid rating value");

        Review memory newReview = Review(msg.sender, _rating, _comment);
        sneakers[_index].reviews.push(newReview);
    }

    function getSneakerReviews(
        uint256 _index
    ) external view returns (Review[] memory) {
        require(_index < sneakersLength, "Sneaker does not exist");
        return sneakers[_index].reviews;
    }

    function getAverageRating(uint256 _index) external view returns (uint256) {
        require(_index < sneakersLength, "Sneaker does not exist");

        uint256 totalRating = 0;
        uint256 reviewsCount = sneakers[_index].reviews.length;

        for (uint256 i = 0; i < reviewsCount; i++) {
            totalRating += sneakers[_index].reviews[i].rating;
        }

        if (reviewsCount > 0) {
            return totalRating / reviewsCount;
        } else {
            return 0;
        }
    }

    /// @return sneaker details with key @index from sneaker mapping
    function getSneaker(
        uint _index
    )
        public
        view
        returns (
            address payable,
            string memory,
            string memory,
            string memory,
            uint,
            uint
        )
    {
        return (
            sneakers[_index].owner,
            sneakers[_index].image,
            sneakers[_index].name,
            sneakers[_index].description,
            sneakers[_index].price,
            sneakers[_index].likesCount
        );
    }

    function buySneaker(uint256 _index) external payable {
        require(_index < sneakersLength, "Invalid index");
        Sneaker storage sneaker = sneakers[_index];
        require(msg.sender != sneaker.owner, "Cannot buy your own sneaker");
        require(msg.value >= sneaker.price, "Insufficient funds");

        address payable seller = sneaker.owner;

        // Transfer ownership
        sneaker.owner = payable(msg.sender);

        // Transfer payment to the seller
        (bool transferSuccess, ) = seller.call{value: sneaker.price}("");
        require(transferSuccess, "Failed to transfer payment to seller");

        emit buySneakerEvent(seller, msg.sender, _index);
    }

    function sellSneaker(uint256 _index, uint256 _price) external {
        require(_index < sneakersLength, "Invalid index");
        Sneaker storage sneaker = sneakers[_index];
        require(msg.sender == sneaker.owner, "Only owner can sell");

        sneaker.price = _price;

        emit sellSneakerEvent(msg.sender, _index, _price);
    }

    /// @dev Delete sneaker with key `_index` from `sneakers` mapping
    function removeSneaker(uint256 _index) external {
        require(msg.sender == sneakers[_index].owner, "Only owner can delete");
        delete sneakers[_index];
        emit deleteSneakerEvent(_index);
    }

    /// @dev Like sneaker with key `_index`
    function likedSneakerEvent(uint256 _index) external {
        require(_index < sneakersLength, "Sneaker does not exist");
        require(!likes[_index][msg.sender], "Sneaker already liked");
        likes[_index][msg.sender] = true;
        sneakers[_index].likesCount++;
        emit likeSneakerEvent(msg.sender, _index);
    }

    //  Get total likes for sneaker with key `_index`
    function getTotalLikes(uint256 _index) external view returns (uint256) {
        require(_index < sneakersLength, "Invalid index");
        return sneakers[_index].likesCount;
    }

    // Get total sneakers count
    function getTotalSneakers() external view returns (uint256) {
        return sneakersLength;
    }
}
