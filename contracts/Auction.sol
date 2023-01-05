//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 *  @title A NFT Marketplace Auction
 *  @author Zig Balthazar
 */

contract NftMarketPlaceAuction is Ownable, ReentrancyGuard, IERC721Receiver {
    struct AuctionItem {
        uint256 index;
        address nft;
        uint256 nftID;
        address creator;
        address currentBidOwner;
        uint256 currentBidPrice;
        uint256 endAuction;
        uint256 bidCount;
    }

    AuctionItem[] public allAuctions;

    mapping(uint256 => mapping(address => uint256)) public fundsByBidder;

    uint256 index;

    event AuctionCreated(
        uint256 indexed _auctionId,
        address indexed nft,
        uint256 _nftId
    );
    event BidPlaced(uint256 indexed _auctionId, address indexed creator);
    event AuctionCanceled(uint256 indexed _auctionId);
    event NftClaimed(uint256 indexed _auction, uint256 indexed _nftId);
    event CreatorFundsClaimed(
        uint256 indexed _auctionId,
        uint256 indexed _amount
    );
    event FundsWithdrawn(
        uint256 indexed _auctionId,
        address indexed _receiver,
        uint256 indexed _amount
    );

    event NftRefunded(uint256 indexed _auctionId, address indexed receiver);

    modifier onlyCreator(uint256 _auctionID) {
        //check if caller is creator
        AuctionItem memory auctionItem = allAuctions[_auctionID];
        require(msg.sender == auctionItem.creator, "Not owner");
        _;
    }

    constructor() {}

    /**
     * @notice Creates an auction for an nft.
     * @param _nft //Nft Contract address
     * @param _nftID // nft id
     * @param _initialBid //minimum bid amount
     * @param _endAuction //maximum time the auction can run.
     */
    function createAuction(
        address _nft,
        uint256 _nftID,
        uint256 _initialBid,
        uint256 _endAuction
    ) external returns (uint256) {
        address _msgSender = msg.sender;
        require(_nft != address(0));
        require(_endAuction >= getTimestamp(), "Invalid Date");

        require(_initialBid != 0, "invalid bid price");

        require(IERC721(_nft).ownerOf(_nftID) == _msgSender, "Not owner");

        require(
            IERC721(_nft).getApproved(_nftID) == address(this),
            "not approved"
        );

        AuctionItem memory newAuction = AuctionItem({
            index: index,
            nft: _nft,
            nftID: _nftID,
            creator: _msgSender,
            currentBidOwner: address(0x0),
            currentBidPrice: _initialBid,
            endAuction: _endAuction,
            bidCount: 0
        });

        allAuctions.push(newAuction);
        index++;

        IERC721(_nft).safeTransferFrom(_msgSender, address(this), _nftID);

        emit AuctionCreated(index, newAuction.nft, newAuction.nftID);

        return index;
    }

    /**
     * @notice Place a bid to a specific auctionID
     * @param _auctionId //Id of the auction to bid.
     */
    function placeBid(uint256 _auctionId) external payable returns (bool) {
        address _msgSender = msg.sender;
        require(isOpen(_auctionId), "Auction Ended");
        require(_auctionId < allAuctions.length, "Invalid index");

        AuctionItem storage auctionItem = allAuctions[_auctionId];

        require(msg.value > auctionItem.currentBidPrice, "Low bid price");

        require(_msgSender != auctionItem.creator, "Creator cant bid");

        address newBidOwner = _msgSender;

        auctionItem.currentBidOwner = newBidOwner;
        auctionItem.currentBidPrice = msg.value;
        auctionItem.bidCount++;

        fundsByBidder[_auctionId][_msgSender] = msg.value;

        emit BidPlaced(_auctionId, _msgSender);

        return true;
    }

    /// @notice Cancels an auction before the auciton ends.
    function cancelAuction(uint256 _auctionId)
        external
        onlyCreator(_auctionId)
    {
        require(isOpen(_auctionId), "Auction Ended");
        require(_auctionId < allAuctions.length, "Invalid index");
        AuctionItem memory auctionItem = allAuctions[_auctionId];

        require(auctionItem.bidCount != 0, "No bid made");

        uint256 currentBidPrice = auctionItem.currentBidPrice;

        _withdraw(msg.sender, currentBidPrice);

        _claimNft(auctionItem, auctionItem.currentBidOwner);

        emit AuctionCanceled(_auctionId);
    }

    ///@notice Claims nft for the winner of the auction.
    function claimNft(uint256 _auctionId) external nonReentrant {
        require(!isOpen(_auctionId), "Auction Open");
        AuctionItem memory auctionItem = allAuctions[_auctionId];

        require(msg.sender == auctionItem.currentBidOwner, "Not Bidder");
        _claimNft(auctionItem, auctionItem.currentBidOwner);

        emit NftClaimed(_auctionId, auctionItem.nftID);
    }

    ///@notice Owner of the auction can withdraw highest bidder funds.
    function claimCreatorFunds(uint256 _auctionId)
        external
        nonReentrant
        onlyCreator(_auctionId)
    {
        require(!isOpen(_auctionId), "Auction Open");
        AuctionItem memory auctionItem = allAuctions[_auctionId];
        uint256 amountToSend = auctionItem.currentBidPrice;
        _withdraw(msg.sender, amountToSend);

        emit CreatorFundsClaimed(_auctionId, amountToSend);
        delete allAuctions[auctionItem.index];
    }

    //@notice Unsuccessful bidders can withdraw their funds
    function withdrawFundsByBidder(uint256 _auctionId) external nonReentrant {
                address _msgSender = msg.sender;

        require(!isOpen(_auctionId), "Auction Open");
        uint256 withdrawAmount = fundsByBidder[_auctionId][_msgSender];

        require(withdrawAmount != 0, "No funds to withdraw");

        fundsByBidder[_auctionId][_msgSender] = 0;

        _withdraw(_msgSender, withdrawAmount);

        emit FundsWithdrawn(_auctionId, _msgSender, withdrawAmount);
    }

    ///@notice nft is refunded when number of bids is zero and auction has also ended.
    function refundNFt(uint256 _auctionId)
        external
        nonReentrant
        onlyCreator(_auctionId)
    {
                address _msgSender = msg.sender;

        require(!isOpen(_auctionId), "Auction Open");
        AuctionItem memory auctionItem = allAuctions[_auctionId];

        require(auctionItem.bidCount == 0, "Cant refund");

        _claimNft(auctionItem, _msgSender);

        emit NftRefunded(_auctionId, _msgSender);
    }

    function _claimNft(AuctionItem memory _auctionItem, address _receiver)
        internal
    {
        fundsByBidder[_auctionItem.index][_auctionItem.currentBidOwner] = 0;

        IERC721(_auctionItem.nft).safeTransferFrom(
            address(this),
            _receiver,
            _auctionItem.nftID
        );
    }

    function _withdraw(address _receiver, uint256 amount) internal {
        (bool sent, ) = _receiver.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    function getTimestamp() public view returns (uint256) {
        return block.timestamp;
    }

    function isOpen(uint256 _auctionId) private view returns (bool) {
        AuctionItem memory auctionItem = allAuctions[_auctionId];

        if (getTimestamp() >= auctionItem.endAuction) return false;
        return true;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
